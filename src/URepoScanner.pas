unit URepoScanner;

interface

uses
  System.Classes, System.DateUtils, System.diagnostics, System.generics.collections, System.IOUtils,
  System.SyncObjs, System.SysUtils, System.Threading, System.Types,

  AutoFree, CancelToken, maxLogic.Logger, maxLogic.IOUtils, maxLogic.StrUtils,
  UAppSettings, UGitClient, UModels, UPathRules, URepoCache, UUiEventQueue;

type
  TRepoScanner = class
  private
    fGit: TGitClient;
    fQueue: TUiEventQueue;
    fCancelToken: iCancelToken;
    fDebugEnabled: Boolean;
    fLogger: iMaxLog;
    fCacheLock: TCriticalSection;
    procedure LogLine(const aText: string; const aLogType: TLogType = TLogType.Info);
    procedure LogDebug(const aText: string);
    procedure PublishScanFinished(const aText: string);
    function IsCancelled: boolean;
    function ResolveIgnorePath(const aSettingsFolder: string; const aExeFolder: string): string;
    function FindCandidates(const aRoot: string; const aTargetName: string; const aDepthLimit: integer;
      const aIgnorePatterns: TArray<TIgnorePattern>;
      out aSkippedDueToCap: boolean): TArray<string>;
    function ResolveRepoTasks(const aCandidates: TArray<string>;
      out aTaskMap: TDictionary < string, TArray<string> > ): TArray<string>;
    function BuildRepoStatus(const aRepoRoot: string; const aMatched: TArray<string>;
      const aCache: TRepoCache; const aTtlSeconds: integer; out aStatus: TRepoStatus): boolean;
  public
    constructor Create(const aGit: TGitClient);
    function TryRefreshRepoStatus(const aSettings: TAppSettings; const aRepoRoot: string;
      const aMatched: TArray<string>; out aStatus: TRepoStatus; out aError: string): Boolean;
    function ExecuteScan(const aSettings: TAppSettings; const aQueue: TUiEventQueue;
      const aCancelToken: iCancelToken): TScanSummary;
  end;

implementation

const
  cMaxGitProbeCandidates = 10000;
  cFetchTimeoutMs = 60000;

  cLogPhase1 = 'Phase 1: finding candidate folders';
  cLogPhase2 = 'Phase 2: resolving repo roots';
  cLogPhase3 = 'Phase 3: checking repo status';
  cLogPhase3Repo = 'Phase 3: repo ';
  cLogSummary = 'Summary';

  cLogCacheLoadFailed = 'Cache load failed: ';
  cLogCacheSaveFailed = 'Cache save failed: ';
  cLogCacheSaved = 'Cache saved.';
  cLogIgnoreLoaded = 'Ignore patterns loaded: ';
  cLogIgnoreFile = 'Ignore file: ';
  cLogCandidates = 'Candidates: ';
  cLogRepoRoots = 'Unique repo roots: ';
  cLogCapHit = 'Hit MaxGitProbeCandidates cap; scan truncated.';
  cLogPhase1Progress = 'Phase 1 progress: %d dirs, %d candidates';
  cLogPhase3Progress = 'Phase 3 progress: %d/%d repos';

resourcestring
  rsFetchSkippedNotWritable = 'skipped fetch (git dir not writable)';

type
  TDirItem = record
    Path: string;
    Depth: integer;
  end;

  TRepoTask = record
    RepoRoot: string;
    Matched: TArray<string>;
  end;

constructor TRepoScanner.Create(const aGit: TGitClient);
begin
  inherited Create;
  fGit := aGit;
end;

function TRepoScanner.TryRefreshRepoStatus(const aSettings: TAppSettings; const aRepoRoot: string;
  const aMatched: TArray<string>; out aStatus: TRepoStatus; out aError: string): Boolean;
var
  g: TGarbos;
  lCache: TRepoCache;
  lCacheErr: string;
  lSettingsFolder: string;
  lCachePath: string;
begin
  aError := '';
  Result := False;

  fQueue := nil;
  fCancelToken := nil;
  fDebugEnabled := aSettings.DebugLogEnabled;
  fLogger := maxLog.CloneWithTag('RepoScanner');
  fCacheLock := nil;
  try
    lSettingsFolder := TAppSettings.GetSettingsFolder;
    if not DirectoryExists(lSettingsFolder) then
      ForceDirectories(lSettingsFolder);

    lCachePath := CombinePath([lSettingsFolder, 'repo-scan-cache.json']);
    GC(lCache, TRepoCache.Create, g);
    if not lCache.LoadFromFile(lCachePath, lCacheErr) then
      aError := lCacheErr;

    if not BuildRepoStatus(aRepoRoot, aMatched, lCache, aSettings.CacheTtlSeconds, aStatus) then
    begin
      if aError = '' then
        aError := 'refresh failed';
      Exit(False);
    end;

    if aStatus.CacheUpdate.Key <> '' then
    begin
      lCache.ApplyUpdate(aStatus.CacheUpdate);
      if not lCache.SaveToFile(lCachePath, aSettings.CacheTtlSeconds, lCacheErr) then
      begin
        if aError = '' then
          aError := lCacheErr;
      end;
    end;

    Result := True;
  finally
    fLogger := nil;
  end;
end;

procedure TRepoScanner.LogDebug(const aText: string);
begin
  if not fDebugEnabled then
    exit;
  if fLogger <> nil then
  begin
    fLogger.Debug(aText);
  end;
end;

procedure TRepoScanner.LogLine(const aText: string; const aLogType: TLogType = TLogType.Info);
var
  lEvent: TUiEvent;
begin
  if fLogger <> nil then
  begin
    case aLogType of
      TLogType.Debug: fLogger.Debug(aText);
      TLogType.Warning: fLogger.Warn(aText);
      TLogType.Error: fLogger.Error(aText);
    else
      fLogger.Info(aText);
    end;
  end;
  lEvent := default(TUiEvent);
  lEvent.kind := TUiEventKind.uekLog;
  lEvent.Text := aText;
  fQueue.Enqueue(lEvent);
end;

procedure TRepoScanner.PublishScanFinished(const aText: string);
var
  lEvent: TUiEvent;
begin
  if fLogger <> nil then
  begin
    fLogger.Info(aText);
  end;

  lEvent := default(TUiEvent);
  lEvent.kind := TUiEventKind.uekProgressEnd;
  fQueue.Enqueue(lEvent);

  lEvent := default(TUiEvent);
  lEvent.kind := TUiEventKind.uekScanFinished;
  lEvent.Text := aText;
  fQueue.Enqueue(lEvent);
end;

function TRepoScanner.IsCancelled: boolean;
begin
  if fCancelToken = nil then
    exit(False);
  Result := fCancelToken.Canceled;
end;

function TRepoScanner.ResolveIgnorePath(const aSettingsFolder: string; const aExeFolder: string): string;
var
  lSettingsIgnore: string;
  lExeIgnore: string;
begin
  lSettingsIgnore := CombinePath([aSettingsFolder, '.ignoredirectory']);
  lExeIgnore := CombinePath([aExeFolder, '.ignoredirectory']);

  if FileExists(lSettingsIgnore) then
    exit(lSettingsIgnore);
  if FileExists(lExeIgnore) then
    exit(lExeIgnore);

  Result := lSettingsIgnore;
end;

function TRepoScanner.FindCandidates(const aRoot: string; const aTargetName: string; const aDepthLimit: integer;
  const aIgnorePatterns: TArray<TIgnorePattern>;
  out aSkippedDueToCap: boolean): TArray<string>;
var
  g: TGarbos;
  lQueue: TQueue<TDirItem>;
  lCandidates: TList<string>;
  lRootFull: string;
  lRootNorm: string;
  lItem: TDirItem;
  lDirs: TStringDynArray;
  lDir: string;
  lName: string;
  lChild: TDirItem;
  lDepth: integer;
  lVisited: integer;
  lSw: TStopWatch;
  lLastUiMs: Int64;
  lLastDebugMs: Int64;
begin
  aSkippedDueToCap := False;
  Result := [];

  lRootFull := TPath.GetFullPath(aRoot);
  lRootNorm := NormalizePathForMatch(lRootFull);

  gc(lQueue, TQueue<TDirItem>.Create, g);
  gc(lCandidates, TList<string>.Create, g);
  lItem.Path := lRootFull;
  lItem.Depth := 0;
  lQueue.Enqueue(lItem);
  lVisited := 0;
  lSw := TStopWatch.startNew;
  lLastUiMs := 0;
  lLastDebugMs := 0;

  while lQueue.Count > 0 do
  begin
    if IsCancelled then
      break;
    lItem := lQueue.Dequeue;
    lDepth := lItem.Depth;
    try
      if not TDirectory.Exists(lItem.Path) then
        continue;

      lDirs := TDirectory.GetDirectories(lItem.Path, '*', TSearchOption.soTopDirectoryOnly);
    except
      Continue;
    end;

    for lDir in lDirs do
    begin
      if IsCancelled then
        break;
      Inc(lVisited);
      lName := ExtractFileName(lDir);
      if ShouldIgnoreDirectory(lDir, lRootNorm, aIgnorePatterns) then
        Continue;

      lChild.Depth := lDepth + 1;
      lChild.Path := lDir;

      if lChild.Depth <= aDepthLimit then
      begin
        if SameText(lName, aTargetName) then
        begin
          lCandidates.Add(lDir);
          if lCandidates.Count >= cMaxGitProbeCandidates then
          begin
            aSkippedDueToCap := True;
            break;
          end;
        end;
      end;

      if lChild.Depth < aDepthLimit then
        lQueue.Enqueue(lChild);

      if (lVisited mod 250 = 0) and (lSw.ElapsedMilliseconds - lLastDebugMs >= 1000) then
      begin
        LogDebug(Format(cLogPhase1Progress, [lVisited, lCandidates.Count]));
        lLastDebugMs := lSw.ElapsedMilliseconds;
      end;

      if lSw.ElapsedMilliseconds - lLastUiMs >= 5000 then
      begin
        LogLine(Format(cLogPhase1Progress, [lVisited, lCandidates.Count]));
        lLastUiMs := lSw.ElapsedMilliseconds;
      end;
    end;

    if aSkippedDueToCap then
      break;
  end;

  Result := lCandidates.ToArray;
end;

function TRepoScanner.ResolveRepoTasks(const aCandidates: TArray<string>;
  out aTaskMap: TDictionary < string, TArray<string> > ): TArray<string>;
var
  g: TGarbos;
  lMap: TDictionary<string, TList<string>>;
  lRoots: TList<string>;
  lCandidate: string;
  lRepoRoot: string;
  lErr: string;
  lList: TList<string>;
  lMatches: TArray<string>;
  lKey: string;
  i: integer;
begin
  aTaskMap := TDictionary < string, TArray<string> > .Create(TFastCaseAwareComparer.OrdinalIgnoreCase);

  gc(lMap, TDictionary < string, TList<string> > .Create(TFastCaseAwareComparer.OrdinalIgnoreCase), g);
  gc(lRoots, TList<string>.Create, g);

  for i := 0 to length(aCandidates) - 1 do
  begin
    if IsCancelled then
      break;
    lCandidate := aCandidates[i];
    if not fGit.TryGetRepoRoot(lCandidate, lRepoRoot, lErr) then
      Continue;

    if not lMap.TryGetValue(lRepoRoot, lList) then
    begin
      lList := TList<string>.Create;
      lMap.Add(lRepoRoot, lList);
      lRoots.Add(lRepoRoot);
    end;
    lList.Add(lCandidate);
  end;

  for lKey in lMap.Keys do
  begin
    lList := lMap[lKey];
    lMatches := lList.ToArray;
    aTaskMap.AddOrSetValue(lKey, lMatches);
    lList.Free;
  end;

  Result := lRoots.ToArray;
end;

function TRepoScanner.BuildRepoStatus(const aRepoRoot: string; const aMatched: TArray<string>;
  const aCache: TRepoCache; const aTtlSeconds: integer; out aStatus: TRepoStatus): boolean;
var
  lIsInside: boolean;
  lErr: string;
  lBranch: string;
  lOriginUrl: string;
  lRemoteName: string;
  lRemoteUrl: string;
  lHasOrigin: boolean;
  lHasRemote: boolean;
  lUpstream: string;
  lCanCompare: boolean;
  lAhead: integer;
  lBehind: integer;
  lStatusLines: TArray<string>;
  lParse: TGitStatusParse;
  lDiag: TGitWriteDiagnostics;
  lCacheEntry: TRepoCacheEntry;
  lDoFetch: boolean;
  lFetchOk: boolean;
  lFetchErr: string;
  lNowUtc: TDateTime;
  lLastFetchUtc: TDateTime;
  lFetchAgeSec: double;
  lCanWriteFetch: boolean;
  lCacheHit: boolean;
  lUpdate: TRepoCacheUpdate;
  lUpErr: string;
  lRes: TGitResult;
  lSymbolic: TGitResult;
  lRefLine: string;
  lSlashPos: integer;
begin
  aStatus := default(TRepoStatus);

  if IsCancelled then
    exit(False);

  LogDebug('Repo start: ' + aRepoRoot);

  if not fGit.TryIsInsideWorkTree(aRepoRoot, lIsInside, lErr) then
    exit(False);
  if not lIsInside then
    exit(False);

  if not fGit.TryGetGitWriteDiagnostics(aRepoRoot, lDiag, lErr) then
    lDiag := default(TGitWriteDiagnostics);

  lCanWriteFetch := True;
  if lDiag.GitDirInfo.Exists then
  begin
    if (not lDiag.GitDirInfo.Writable) or lDiag.GitDirInfo.ReadOnly then
      lCanWriteFetch := False;
  end;
  if lDiag.ModulesInfo.Exists then
  begin
    if (not lDiag.ModulesInfo.Writable) or lDiag.ModulesInfo.ReadOnly then
      lCanWriteFetch := False;
  end;

  if not fGit.TryGetBranch(aRepoRoot, lBranch, lErr) then
    lBranch := rsBranchUnknown;

  if not fGit.TryGetOriginUrl(aRepoRoot, lOriginUrl, lErr) then
    lOriginUrl := '';
  lHasOrigin := lOriginUrl <> '';

  lUpstream := '';
  if not fGit.TryGetUpstream(aRepoRoot, lUpstream, lUpErr) then
    lUpstream := '';

  if (lUpstream = '') and lHasOrigin and (lBranch <> rsBranchDetached) and (lBranch <> rsBranchUnknown) then
  begin
    if fGit.TryRunGit(aRepoRoot, ['show-ref', '--verify', '--quiet', 'refs/remotes/origin/' + lBranch], lRes, lErr, 0) then
    begin
      if lRes.ExitCode = 0 then
        lUpstream := 'origin/' + lBranch;
    end;
  end;

  if (lUpstream = '') and lHasOrigin then
  begin
    if fGit.TryRunGit(aRepoRoot, ['symbolic-ref', '-q', 'refs/remotes/origin/HEAD'], lSymbolic, lErr, 0) then
    begin
      if lSymbolic.ExitCode = 0 then
      begin
        if length(lSymbolic.OutputLines) > 0 then
        begin
          lRefLine := lSymbolic.OutputLines[0].Trim;
          if lRefLine.StartsWith('refs/remotes/') then
            lUpstream := lRefLine.Replace('refs/remotes/', '');
        end;
      end;
    end;
  end;

  lRemoteName := '';
  lRemoteUrl := '';
  if lUpstream <> '' then
  begin
    lSlashPos := lUpstream.IndexOf('/');
    if lSlashPos > 0 then
      lRemoteName := lUpstream.Substring(0, lSlashPos);
  end;

  if lRemoteName <> '' then
  begin
    if SameText(lRemoteName, 'origin') then
      lRemoteUrl := lOriginUrl
    else if not fGit.TryGetRemoteUrl(aRepoRoot, lRemoteName, lRemoteUrl, lErr) then
      lRemoteUrl := '';
  end;

  if (lRemoteName = '') and lHasOrigin then
  begin
    lRemoteName := 'origin';
    lRemoteUrl := lOriginUrl;
  end;

  lHasRemote := lRemoteName <> '';

  lDoFetch := False;
  lFetchOk := True;
  lFetchErr := '';
  lCacheHit := False;
  if lHasRemote then
  begin
    if aTtlSeconds <= 0 then
    begin
      lDoFetch := True;
    end else begin
      if fCacheLock <> nil then
        fCacheLock.Enter;
      try
        lCacheHit := aCache.TryGet(aRepoRoot.ToLowerInvariant, lCacheEntry);
      finally
        if fCacheLock <> nil then
          fCacheLock.Leave;
      end;
    end;

    if lCacheHit then
    begin
      if lCacheEntry.LastFetchUtc <> '' then
      begin
        if TryISO8601ToDate(lCacheEntry.LastFetchUtc, lLastFetchUtc, True) then
        begin
          lNowUtc := TTimeZone.Local.ToUniversalTime(now);
          lFetchAgeSec := (lNowUtc - lLastFetchUtc) * SecsPerDay;
          if lFetchAgeSec > aTtlSeconds then
            lDoFetch := True;
        end else begin
          lDoFetch := True;
        end;
      end else begin
        lDoFetch := True;
      end;
    end else begin
      lDoFetch := True;
    end;

    if lDoFetch then
    begin
      if IsCancelled then
        exit(False);
      if not lCanWriteFetch then
      begin
        lFetchOk := False;
        lFetchErr := rsFetchSkippedNotWritable;
      end else begin
        if IsCancelled then
          exit(False);
        lFetchOk := fGit.TryFetchRemote(aRepoRoot, lRemoteName, cFetchTimeoutMs, lFetchErr);
      end;
      if lFetchOk then
        LogDebug('Fetch ok: ' + aRepoRoot)
      else
        LogDebug('Fetch failed: ' + aRepoRoot + ' - ' + lFetchErr);
    end;
  end;

  if IsCancelled then
    exit(False);

  lStatusLines := [];
  if not fGit.TryGetStatusPorcelain(aRepoRoot, lStatusLines, lErr) then
    lStatusLines := [];
  lParse := TGitClient.ParseStatusPorcelain(lStatusLines);

  lAhead := 0;
  lBehind := 0;
  lCanCompare := lHasRemote and (lUpstream <> '');
  if lCanCompare then
  begin
    if IsCancelled then
      exit(False);
    fGit.TryGetAheadBehind(aRepoRoot, lUpstream, lAhead, lBehind, lErr);
  end;

  aStatus.RepoRoot := aRepoRoot;
  aStatus.MatchedFolders := aMatched;
  aStatus.Branch := lBranch;
  aStatus.HasOrigin := lHasRemote;
  aStatus.Upstream := lUpstream;
  aStatus.CanCompare := lCanCompare;
  aStatus.Ahead := lAhead;
  aStatus.Behind := lBehind;
  aStatus.IsOutOfDate := lCanCompare and (lBehind > 0);
  aStatus.HasUnpushed := lCanCompare and (lAhead > 0);
  aStatus.IsDirty := lParse.HasStaged or lParse.HasUnstaged or lParse.HasUntracked;
  aStatus.DirtySummary := lParse.Summary;
  aStatus.FetchFailed := lDoFetch and not lFetchOk;
  aStatus.FetchError := lFetchErr;
  aStatus.HasProblem := aStatus.FetchFailed or aStatus.IsDirty or aStatus.IsOutOfDate or
    aStatus.HasUnpushed or (not aStatus.HasOrigin) or (aStatus.HasOrigin and (aStatus.Upstream = ''));

  aStatus.GitDirPath := lDiag.GitDirPath;
  aStatus.GitDirWritable := lDiag.GitDirInfo.Writable;
  aStatus.GitDirReadOnly := lDiag.GitDirInfo.ReadOnly;
  aStatus.GitDirError := lDiag.GitDirInfo.Error;
  aStatus.ModulesDirPath := lDiag.ModulesPath;
  aStatus.ModulesDirWritable := lDiag.ModulesInfo.Writable;
  aStatus.ModulesDirReadOnly := lDiag.ModulesInfo.ReadOnly;
  aStatus.ModulesDirError := lDiag.ModulesInfo.Error;

  if lDoFetch then
  begin
    lUpdate := default(TRepoCacheUpdate);
    lUpdate.Key := aRepoRoot.ToLowerInvariant;
    lUpdate.OriginUrl := lRemoteUrl;
    lUpdate.LastFetchUtc := DateToISO8601(TTimeZone.Local.ToUniversalTime(now), True);
    lUpdate.LastFetchOk := lFetchOk;
    lUpdate.LastFetchError := lFetchErr;
    lUpdate.HasLastFetchOk := True;
    aStatus.CacheUpdate := lUpdate;
  end;

  LogDebug('Repo done: ' + aRepoRoot + ' problem=' + BoolToStr(aStatus.HasProblem, True));

  Result := True;
end;

function TRepoScanner.ExecuteScan(const aSettings: TAppSettings; const aQueue: TUiEventQueue;
  const aCancelToken: iCancelToken): TScanSummary;
var
  g: TGarbos;
  lSw: TStopWatch;
  lSettingsFolder: string;
  lExeFolder: string;
  lIgnorePath: string;
  lIgnorePatterns: TArray<TIgnorePattern>;
  lCandidates: TArray<string>;
  lSkipped: boolean;
  lRepoRoots: TArray<string>;
  lMap: TDictionary<string, TArray<string>>;
  lTasks: TArray<TRepoTask>;
  lIndex: integer;
  lResults: TList<TRepoStatus>;
  lLock: TCriticalSection;
  lCacheLock: TCriticalSection;
  lDone: integer;
  lMaxThreads: integer;
  lPool: TThreadPool;
  lCache: TRepoCache;
  lCacheErr: string;
  lStatus: TRepoStatus;
  lEvent: TUiEvent;
  lProblemCount: integer;
  lCleanCount: integer;
  lTaskCount: integer;
begin
  Result := default(TScanSummary);
  fQueue := aQueue;
  fCancelToken := aCancelToken;
  fDebugEnabled := aSettings.DebugLogEnabled;
  fLogger := maxLog.CloneWithTag('RepoScanner');
  fCacheLock := nil;

  lSw := TStopWatch.startNew;

  lSettingsFolder := TAppSettings.GetSettingsFolder;
  lExeFolder := ExtractFilePath(ParamStr(0));
  if not DirectoryExists(lSettingsFolder) then
  begin
    ForceDirectories(lSettingsFolder);
  end;

  if fDebugEnabled then
  begin
    LogDebug('=== Scan debug log ===');
    LogDebug('Timestamp: ' + DateToISO8601(TTimeZone.Local.ToUniversalTime(now), True));
    LogDebug('StartPath: ' + aSettings.StartPath);
    LogDebug('MaxDepth: ' + IntToStr(aSettings.MaxDepth));
    LogDebug('ThrottleLimit: ' + IntToStr(aSettings.ThrottleLimit));
    LogDebug('CacheTtlSeconds: ' + IntToStr(aSettings.CacheTtlSeconds));
    if aSettings.DebugLogPath <> '' then
    begin
      LogDebug('DebugLogPath: ' + aSettings.DebugLogPath);
    end;
  end;

  LogDebug('ExeFolder: ' + lExeFolder);
  LogDebug('SettingsFolder: ' + lSettingsFolder);

  lIgnorePath := ResolveIgnorePath(lSettingsFolder, lExeFolder);
  lIgnorePatterns := LoadIgnorePatterns(lIgnorePath);
  LogLine(cLogIgnoreFile + lIgnorePath);
  LogLine(cLogIgnoreLoaded + IntToStr(length(lIgnorePatterns)));

  lEvent := default(TUiEvent);
  lEvent.kind := TUiEventKind.uekProgressStart;
  lEvent.ProgressMode := TProgressMode.pmIndeterminate;
  fQueue.Enqueue(lEvent);

  gc(lCache, TRepoCache.Create, g);
  try
    if not lCache.LoadFromFile(CombinePath([lSettingsFolder, 'repo-scan-cache.json']), lCacheErr) then
      LogLine(cLogCacheLoadFailed + lCacheErr, TLogType.Warning);

    LogLine(cLogPhase1);
    lCandidates := FindCandidates(aSettings.StartPath, aSettings.TargetRepoName, aSettings.MaxDepth,
      lIgnorePatterns, lSkipped);
    Result.CandidateCount := length(lCandidates);
    Result.SkippedDueToCap := lSkipped;
    LogLine(cLogCandidates + IntToStr(Result.CandidateCount));
    if lSkipped then
      LogLine(cLogCapHit);

    if IsCancelled then
    begin
      PublishScanFinished(cLogSummary + ': cancelled');
      exit;
    end;

    LogLine(cLogPhase2);
    lRepoRoots := ResolveRepoTasks(lCandidates, lMap);
    try
      Result.RepoCount := length(lRepoRoots);
      LogLine(cLogRepoRoots + IntToStr(Result.RepoCount));
      if Result.SkippedDueToCap then
        LogLine(cLogCapHit);

      if IsCancelled then
      begin
        PublishScanFinished(cLogSummary + ': cancelled');
        exit;
      end;

      LogLine(cLogPhase3);

      gc(lResults, TList<TRepoStatus>.Create, g);
      gc(lLock, TCriticalSection.Create, g);
      gc(lCacheLock, TCriticalSection.Create, g);
      fCacheLock := lCacheLock;

      lTaskCount := length(lRepoRoots);
      SetLength(lTasks, lTaskCount);
      for lIndex := 0 to lTaskCount - 1 do
      begin
        lTasks[lIndex].RepoRoot := lRepoRoots[lIndex];
        if lMap.TryGetValue(lRepoRoots[lIndex], lTasks[lIndex].Matched) then
        else begin
          lTasks[lIndex].Matched := [];
        end;
      end;

      lEvent := default(TUiEvent);
      lEvent.kind := TUiEventKind.uekProgressStart;
      lEvent.ProgressMode := TProgressMode.pmDeterminate;
      lEvent.ProgressMax := lTaskCount;
      lEvent.ProgressValue := 0;
      fQueue.Enqueue(lEvent);

      lDone := 0;
      if aSettings.ThrottleLimit > 0 then
        lMaxThreads := aSettings.ThrottleLimit
      else
        lMaxThreads := 1;

      if lTaskCount > 0 then
      begin
        gc(lPool, TThreadPool.Create, g);
        lPool.UnlimitedWorkerThreadsWhenBlocked := False;
        lPool.SetMaxWorkerThreads(lMaxThreads);
        lPool.SetMinWorkerThreads(lMaxThreads);

        TParallel.for(0, lTaskCount - 1,
          procedure(aIndex: integer; aLoopState: TParallel.TLoopState)
          var
            lLocalStatus: TRepoStatus;
            lLocalEvent: TUiEvent;
            lLocalDone: integer;
          begin
            if IsCancelled then
              exit;

            LogLine(cLogPhase3Repo + lTasks[aIndex].RepoRoot);

            if BuildRepoStatus(lTasks[aIndex].RepoRoot, lTasks[aIndex].Matched, lCache, aSettings.CacheTtlSeconds, lLocalStatus) then
            begin
              if IsCancelled then
                exit;
              lLock.Enter;
              try
                lResults.Add(lLocalStatus);
              finally
                lLock.Leave;
              end;

              lLocalEvent := default(TUiEvent);
              lLocalEvent.kind := TUiEventKind.uekRepoResult;
              lLocalEvent.RepoStatus := lLocalStatus;
              fQueue.Enqueue(lLocalEvent);
            end;

            if IsCancelled then
              exit;

            lLocalDone := TInterlocked.Increment(lDone);
            lLocalEvent := default(TUiEvent);
            lLocalEvent.kind := TUiEventKind.uekProgressUpdate;
            lLocalEvent.ProgressValue := lLocalDone;
            fQueue.Enqueue(lLocalEvent);

            if (lLocalDone mod 100 = 0) or (lLocalDone = lTaskCount) then
              LogDebug(Format(cLogPhase3Progress, [lLocalDone, lTaskCount]));
          end,
          lPool);
      end else begin
        lEvent := default(TUiEvent);
        lEvent.kind := TUiEventKind.uekProgressUpdate;
        lEvent.ProgressValue := 0;
        fQueue.Enqueue(lEvent);
      end;

      if IsCancelled then
      begin
        PublishScanFinished(cLogSummary + ': cancelled');
        exit;
      end;

      lProblemCount := 0;
      lCleanCount := 0;
      for lStatus in lResults do
      begin
        if lStatus.HasProblem then
          Inc(lProblemCount)
        else
          Inc(lCleanCount);
        if lStatus.CacheUpdate.Key <> '' then
          lCache.ApplyUpdate(lStatus.CacheUpdate);
      end;

      Result.ProblemCount := lProblemCount;
      Result.CleanCount := lCleanCount;

      lEvent := default(TUiEvent);
      lEvent.kind := TUiEventKind.uekProgressEnd;
      fQueue.Enqueue(lEvent);

      if not lCache.SaveToFile(CombinePath([lSettingsFolder, 'repo-scan-cache.json']), aSettings.CacheTtlSeconds, lCacheErr) then
        LogLine(cLogCacheSaveFailed + lCacheErr, TLogType.Warning)
      else
        LogLine(cLogCacheSaved);

      lEvent := default(TUiEvent);
      lEvent.kind := TUiEventKind.uekScanFinished;
      lEvent.Text := Format('%s: %d repos, %d needs attention, %d clean, %d candidates in %d ms',
        [cLogSummary, Result.RepoCount, Result.ProblemCount, Result.CleanCount, Result.CandidateCount,
          lSw.ElapsedMilliseconds]);
      fQueue.Enqueue(lEvent);
    finally
      lMap.Free;
    end;
  finally
    fCacheLock := nil;
    fLogger := nil;
  end;
end;

end.
