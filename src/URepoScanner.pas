unit URepoScanner;

interface

uses
  System.Classes, System.DateUtils, System.diagnostics, System.generics.collections, System.IOUtils,
  System.Masks, System.SyncObjs, System.SysUtils, System.Threading, System.Types,

  AutoFree, CancelToken, maxLogic.Logger, maxLogic.IOUtils, maxLogic.StrUtils,
  UAppSettings, UGitClient, UModels, UPathRules, URepoCache, UUiEventQueue;

type
  TRepoFetchPlan = record
    NeedsFetch: Boolean;
    CacheHit: Boolean;
    CanWrite: Boolean;
    RemoteName: string;
    RemoteUrl: string;
  end;

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
  protected
    fGeneration: Int64;
    function NewUiEvent(const aKind: TUiEventKind): TUiEvent;
    function FindRepoCandidates(const aRoots: TArray<string>; const aFilterPattern: string;
      const aDepthLimit: Integer; const aIgnorePatterns: TArray<TIgnorePattern>;
      out aSkippedDueToCap: Boolean; const aQueue: TUiEventQueue = nil): TArray<string>;
    function PublishCachedInventory(const aCache: TRepoCache; const aFingerprint: string;
      const aQueue: TUiEventQueue): Integer;
    function BuildRepoStatus(const aRepoRoot: string; const aMatched: TArray<string>;
      const aCache: TRepoCache; const aTtlSeconds: integer; out aStatus: TRepoStatus): boolean;
    function BuildLocalRepoStatus(const aRepoRoot: string; const aMatched: TArray<string>;
      const aCache: TRepoCache; const aTtlSeconds: Integer; out aStatus: TRepoStatus;
      out aFetchPlan: TRepoFetchPlan): Boolean;
    function RefreshRepoStatus(const aRepoRoot: string; const aMatched: TArray<string>;
      const aCache: TRepoCache; const aTtlSeconds: Integer; const aFetchPlan: TRepoFetchPlan;
      var aStatus: TRepoStatus): Boolean;
    function CheckRepoStatusLocalFirst(const aRepoRoot: string; const aMatched: TArray<string>;
      const aCache: TRepoCache; const aTtlSeconds: Integer; const aQueue: TUiEventQueue;
      out aStatus: TRepoStatus): Boolean; overload;
    function CheckRepoStatusLocalFirst(const aRepoRoot: string; const aMatched: TArray<string>;
      const aCache: TRepoCache; const aTtlSeconds: Integer; const aQueue: TUiEventQueue;
      out aStatus: TRepoStatus; out aFetchSkippedByCache, aFetchAttempted: Boolean): Boolean; overload;
  public
    constructor Create(const aGit: TGitClient);
    function TryRefreshRepoStatus(const aSettings: TAppSettings; const aRepoRoot: string;
      const aMatched: TArray<string>; out aStatus: TRepoStatus; out aError: string): Boolean;
    function ExecuteScan(const aSettings: TAppSettings; const aQueue: TUiEventQueue;
      const aCancelToken: iCancelToken): TScanSummary; overload;
    function ExecuteScan(const aSettings: TAppSettings; const aQueue: TUiEventQueue;
      const aCancelToken: iCancelToken; const aGeneration: Int64): TScanSummary; overload;
  end;

implementation

const
  cMaxGitProbeCandidates = 10000;
  cFetchTimeoutMs = 60000;

  cLogPhase1 = 'Phase 1: finding candidate folders';
  cLogPhase3 = 'Phase 3: checking repo status';
  cLogPhase3Repo = 'Phase 3: repo ';
  cLogSummary = 'Summary';

  cLogCacheLoadFailed = 'Cache load failed: ';
  cLogCacheSaveFailed = 'Cache save failed: ';
  cLogCacheSaved = 'Cache saved.';
  cLogCachedInventory = 'Cached repository inventory: %d valid rows';
  cLogIgnoreLoaded = 'Ignore patterns loaded: ';
  cLogIgnoreFile = 'Ignore file: ';
  cLogCandidates = 'Candidates: ';
  cLogRepoRoots = 'Unique repo roots: ';
  cLogCapHit = 'Hit MaxGitProbeCandidates cap; scan truncated.';
  cLogPhase1Progress = 'Phase 1 progress: %d dirs, %d candidates';
  cLogPhase3Progress = 'Phase 3 progress: %d/%d repos';
  cLogPhaseComplete = '%s completed in %d ms';
  cLogFetchCache = 'Fetch cache: %d fresh skips, %d refreshes';
  cLogQueuePeak = 'UI queue peak: %d events';

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

function TRepoScanner.NewUiEvent(const aKind: TUiEventKind): TUiEvent;
begin
  Result := Default(TUiEvent);
  Result.Kind := aKind;
  Result.Generation := fGeneration;
end;

function TRepoScanner.PublishCachedInventory(const aCache: TRepoCache; const aFingerprint: string;
  const aQueue: TUiEventQueue): Integer;
var
  lEvent: TUiEvent;
  lRepoRoot: string;
begin
  Result := 0;
  for lRepoRoot in aCache.GetValidInventory(aFingerprint) do
  begin
    lEvent := NewUiEvent(TUiEventKind.uekRepoWaiting);
    lEvent.RepoRoot := lRepoRoot;
    aQueue.Enqueue(lEvent);
    Inc(Result);
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
  lEvent := NewUiEvent(TUiEventKind.uekLog);
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

  lEvent := NewUiEvent(TUiEventKind.uekProgressEnd);
  fQueue.Enqueue(lEvent);

  lEvent := NewUiEvent(TUiEventKind.uekScanFinished);
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

function TRepoScanner.FindRepoCandidates(const aRoots: TArray<string>; const aFilterPattern: string;
  const aDepthLimit: Integer; const aIgnorePatterns: TArray<TIgnorePattern>;
  out aSkippedDueToCap: Boolean; const aQueue: TUiEventQueue): TArray<string>;
var
  g: TGarbos;
  lQueue: TQueue<TDirItem>;
  lCandidates: TList<string>;
  lCandidateSet: TDictionary<string, Boolean>;
  lRoot: string;
  lRootFull: string;
  lRootNorm: string;
  lItem: TDirItem;
  lChild: TDirItem;
  lDirs: TStringDynArray;
  lDir: string;
  lName: string;
  lRelative: string;
  lPattern: string;
  lVisited: Integer;
  lSw: TStopWatch;
  lLastUiMs: Int64;
  lLastDebugMs: Int64;
  lEvent: TUiEvent;
begin
  aSkippedDueToCap := False;
  Result := [];
  if aDepthLimit < 0 then
    Exit;

  lPattern := Trim(aFilterPattern).ToLowerInvariant;
  if lPattern = '' then
    lPattern := '*';

  GC(lQueue, TQueue<TDirItem>.Create, g);
  GC(lCandidates, TList<string>.Create, g);
  GC(lCandidateSet, TDictionary<string, Boolean>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase), g);
  lVisited := 0;
  lSw := TStopWatch.StartNew;
  lLastUiMs := 0;
  lLastDebugMs := 0;

  for lRoot in aRoots do
  begin
    if IsCancelled then
      Break;
    if Trim(lRoot) = '' then
      Continue;
    try
      lRootFull := TPath.GetFullPath(lRoot);
    except
      Continue;
    end;
    if not TDirectory.Exists(lRootFull) then
      Continue;

    lRootNorm := NormalizePathForMatch(lRootFull);
    if ShouldIgnoreDirectory(lRootFull, lRootNorm, aIgnorePatterns) then
      Continue;

    lQueue.Clear;
    lItem.Path := lRootFull;
    lItem.Depth := 0;
    lQueue.Enqueue(lItem);

    while lQueue.Count > 0 do
    begin
      if IsCancelled then
        Break;
      lItem := lQueue.Dequeue;
      Inc(lVisited);

      if ShouldIgnoreDirectory(lItem.Path, lRootNorm, aIgnorePatterns) then
        Continue;

      if DirectoryExists(TPath.Combine(lItem.Path, '.git')) or
        FileExists(TPath.Combine(lItem.Path, '.git')) then
      begin
        lName := ExtractFileName(ExcludeTrailingPathDelimiter(lItem.Path)).ToLowerInvariant;
        lRelative := GetRelativeForMatch(NormalizePathForMatch(lItem.Path), lRootNorm);
        if MatchesMask(lName, lPattern) or MatchesMask(lRelative, lPattern) then
        begin
          if not lCandidateSet.ContainsKey(lItem.Path) then
          begin
            lCandidateSet.Add(lItem.Path, True);
            lCandidates.Add(lItem.Path);
            if aQueue <> nil then
            begin
              lEvent := NewUiEvent(TUiEventKind.uekRepoWaiting);
              lEvent.RepoRoot := lItem.Path;
              aQueue.Enqueue(lEvent);
            end;
            if lCandidates.Count >= cMaxGitProbeCandidates then
            begin
              aSkippedDueToCap := True;
              Break;
            end;
          end;
        end;
      end;

      if lItem.Depth >= aDepthLimit then
        Continue;
      try
        lDirs := TDirectory.GetDirectories(lItem.Path, '*', TSearchOption.soTopDirectoryOnly);
      except
        Continue;
      end;

      for lDir in lDirs do
      begin
        if IsCancelled then
          Break;
        if SameText(ExtractFileName(lDir), '.git') then
          Continue;
        if ShouldIgnoreDirectory(lDir, lRootNorm, aIgnorePatterns) then
          Continue;
        lChild.Path := lDir;
        lChild.Depth := lItem.Depth + 1;
        lQueue.Enqueue(lChild);
      end;

      if (lVisited mod 250 = 0) and (lSw.ElapsedMilliseconds - lLastDebugMs >= 1000) then
      begin
        LogDebug(Format(cLogPhase1Progress, [lVisited, lCandidates.Count]));
        lLastDebugMs := lSw.ElapsedMilliseconds;
      end;
      if (fQueue <> nil) and (lSw.ElapsedMilliseconds - lLastUiMs >= 5000) then
      begin
        LogLine(Format(cLogPhase1Progress, [lVisited, lCandidates.Count]));
        lLastUiMs := lSw.ElapsedMilliseconds;
      end;
    end;

    if aSkippedDueToCap then
      Break;
  end;

  Result := lCandidates.ToArray;
end;

function TRepoScanner.BuildLocalRepoStatus(const aRepoRoot: string; const aMatched: TArray<string>;
  const aCache: TRepoCache; const aTtlSeconds: Integer; out aStatus: TRepoStatus;
  out aFetchPlan: TRepoFetchPlan): Boolean;
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
  lNowUtc: TDateTime;
  lLastFetchUtc: TDateTime;
  lFetchAgeSec: double;
  lUpErr: string;
  lRes: TGitResult;
  lSymbolic: TGitResult;
  lRefLine: string;
  lSlashPos: integer;
  lGitDirNorm: string;
  lIsSubmodule: Boolean;
  lSuperprojectRoot: string;
  lSubmoduleMainRef: string;
  lCanFastForwardToMain: Boolean;
  lShouldCheckMainFastForward: Boolean;
  lFfRes: TGitResult;
begin
  aStatus := default(TRepoStatus);
  aFetchPlan := Default(TRepoFetchPlan);

  if IsCancelled then
    exit(False);

  LogDebug('Repo start: ' + aRepoRoot);

  if not fGit.TryIsInsideWorkTree(aRepoRoot, lIsInside, lErr) then
    exit(False);
  if not lIsInside then
    exit(False);

  if not fGit.TryGetGitWriteDiagnostics(aRepoRoot, lDiag, lErr) then
    lDiag := default(TGitWriteDiagnostics);

  aFetchPlan.CanWrite := True;
  if lDiag.GitDirInfo.Exists then
  begin
    if (not lDiag.GitDirInfo.Writable) or lDiag.GitDirInfo.ReadOnly then
      aFetchPlan.CanWrite := False;
  end;
  if lDiag.ModulesInfo.Exists then
  begin
    if (not lDiag.ModulesInfo.Writable) or lDiag.ModulesInfo.ReadOnly then
      aFetchPlan.CanWrite := False;
  end;

  lIsSubmodule := False;
  if lDiag.GitMarkerIsFile and (lDiag.GitDirPath <> '') then
  begin
    lGitDirNorm := lDiag.GitDirPath.Replace('/', '\').ToLowerInvariant;
    lIsSubmodule := lGitDirNorm.Contains('\.git\modules\');
  end;
  lSuperprojectRoot := '';
  if lIsSubmodule then
  begin
    if not fGit.TryGetSuperprojectRoot(aRepoRoot, lSuperprojectRoot, lErr) then
      lSuperprojectRoot := '';
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
  aFetchPlan.RemoteName := lRemoteName;
  aFetchPlan.RemoteUrl := lRemoteUrl;

  aFetchPlan.NeedsFetch := False;
  aFetchPlan.CacheHit := False;
  if lHasRemote then
  begin
    if aTtlSeconds <= 0 then
    begin
      aFetchPlan.NeedsFetch := True;
    end else begin
      if fCacheLock <> nil then
        fCacheLock.Enter;
      try
        aFetchPlan.CacheHit := aCache.TryGet(aRepoRoot.ToLowerInvariant, lCacheEntry);
      finally
        if fCacheLock <> nil then
          fCacheLock.Leave;
      end;
    end;

    if aFetchPlan.CacheHit then
    begin
      if lCacheEntry.LastFetchUtc <> '' then
      begin
        if TryISO8601ToDate(lCacheEntry.LastFetchUtc, lLastFetchUtc, True) then
        begin
          lNowUtc := TTimeZone.Local.ToUniversalTime(now);
          lFetchAgeSec := (lNowUtc - lLastFetchUtc) * SecsPerDay;
          if lFetchAgeSec > aTtlSeconds then
            aFetchPlan.NeedsFetch := True;
        end else begin
          aFetchPlan.NeedsFetch := True;
        end;
      end else begin
        aFetchPlan.NeedsFetch := True;
      end;
    end else begin
      aFetchPlan.NeedsFetch := True;
    end;
  end;

  lSubmoduleMainRef := '';
  lCanFastForwardToMain := True;
  lShouldCheckMainFastForward := False;
  if lHasOrigin then
  begin
    if fGit.TryGetPreferredOriginMainRef(aRepoRoot, lSubmoduleMainRef, lErr) and (lSubmoduleMainRef <> '') then
    begin
      lShouldCheckMainFastForward := lIsSubmodule or SameText(lUpstream, lSubmoduleMainRef);
      if lShouldCheckMainFastForward and
        fGit.TryRunGit(aRepoRoot, ['merge-base', '--is-ancestor', 'HEAD', lSubmoduleMainRef], lFfRes, lErr, 0) then
      begin
        if lFfRes.ExitCode = 1 then
          lCanFastForwardToMain := False;
      end;
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
  aStatus.IsSubmodule := lIsSubmodule;
  aStatus.SuperprojectRoot := lSuperprojectRoot;
  aStatus.SubmoduleMainRemoteRef := lSubmoduleMainRef;
  aStatus.SubmoduleNeedsMainFastForward := lShouldCheckMainFastForward and (not lCanFastForwardToMain);
  aStatus.HasOrigin := lHasRemote;
  aStatus.Upstream := lUpstream;
  aStatus.CanCompare := lCanCompare;
  aStatus.Ahead := lAhead;
  aStatus.Behind := lBehind;
  aStatus.IsOutOfDate := lCanCompare and (lBehind > 0);
  aStatus.HasUnpushed := lCanCompare and (lAhead > 0);
  aStatus.IsDirty := lParse.HasStaged or lParse.HasUnstaged or lParse.HasUntracked;
  aStatus.DirtySummary := lParse.Summary;
  aStatus.FetchFailed := False;
  aStatus.FetchError := '';
  aStatus.HasProblem := aStatus.FetchFailed or aStatus.IsDirty or aStatus.IsOutOfDate or
    aStatus.HasUnpushed or (not aStatus.HasOrigin) or (aStatus.HasOrigin and (aStatus.Upstream = '')) or
    aStatus.SubmoduleNeedsMainFastForward;

  aStatus.GitDirPath := lDiag.GitDirPath;
  aStatus.GitDirWritable := lDiag.GitDirInfo.Writable;
  aStatus.GitDirReadOnly := lDiag.GitDirInfo.ReadOnly;
  aStatus.GitDirError := lDiag.GitDirInfo.Error;
  aStatus.ModulesDirPath := lDiag.ModulesPath;
  aStatus.ModulesDirWritable := lDiag.ModulesInfo.Writable;
  aStatus.ModulesDirReadOnly := lDiag.ModulesInfo.ReadOnly;
  aStatus.ModulesDirError := lDiag.ModulesInfo.Error;

  LogDebug('Local repo status: ' + aRepoRoot + ' problem=' + BoolToStr(aStatus.HasProblem, True));

  Result := True;
end;

function TRepoScanner.RefreshRepoStatus(const aRepoRoot: string; const aMatched: TArray<string>;
  const aCache: TRepoCache; const aTtlSeconds: Integer; const aFetchPlan: TRepoFetchPlan;
  var aStatus: TRepoStatus): Boolean;
var
  lFetchError: string;
  lFetchOk: Boolean;
  lRefreshPlan: TRepoFetchPlan;
  lRefreshedStatus: TRepoStatus;
  lUpdate: TRepoCacheUpdate;
begin
  Result := True;
  if not aFetchPlan.NeedsFetch then
    Exit;
  if IsCancelled then
    Exit(False);

  if not aFetchPlan.CanWrite then
  begin
    lFetchOk := False;
    lFetchError := rsFetchSkippedNotWritable;
  end else begin
    lFetchOk := fGit.TryFetchRemote(aRepoRoot, aFetchPlan.RemoteName, cFetchTimeoutMs, lFetchError);
  end;

  if IsCancelled then
    Exit(False);
  if lFetchOk then
  begin
    if not BuildLocalRepoStatus(aRepoRoot, aMatched, aCache, aTtlSeconds,
      lRefreshedStatus, lRefreshPlan) then
      Exit(False);
    aStatus := lRefreshedStatus;
    LogDebug('Fetch ok: ' + aRepoRoot);
  end else begin
    LogDebug('Fetch failed: ' + aRepoRoot + ' - ' + lFetchError);
  end;

  aStatus.FetchFailed := not lFetchOk;
  aStatus.FetchError := lFetchError;
  aStatus.HasProblem := aStatus.FetchFailed or aStatus.HasProblem;
  lUpdate := Default(TRepoCacheUpdate);
  lUpdate.Key := aRepoRoot.ToLowerInvariant;
  lUpdate.OriginUrl := aFetchPlan.RemoteUrl;
  lUpdate.LastFetchUtc := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
  lUpdate.LastFetchOk := lFetchOk;
  lUpdate.LastFetchError := lFetchError;
  lUpdate.HasLastFetchOk := True;
  aStatus.CacheUpdate := lUpdate;
end;

function TRepoScanner.BuildRepoStatus(const aRepoRoot: string; const aMatched: TArray<string>;
  const aCache: TRepoCache; const aTtlSeconds: integer; out aStatus: TRepoStatus): boolean;
var
  lFetchPlan: TRepoFetchPlan;
begin
  Result := BuildLocalRepoStatus(aRepoRoot, aMatched, aCache, aTtlSeconds, aStatus, lFetchPlan);
  if Result and lFetchPlan.NeedsFetch then
    Result := RefreshRepoStatus(aRepoRoot, aMatched, aCache, aTtlSeconds, lFetchPlan, aStatus);
end;

function TRepoScanner.CheckRepoStatusLocalFirst(const aRepoRoot: string;
  const aMatched: TArray<string>; const aCache: TRepoCache; const aTtlSeconds: Integer;
  const aQueue: TUiEventQueue; out aStatus: TRepoStatus): Boolean;
var
  lFetchAttempted: Boolean;
  lFetchSkippedByCache: Boolean;
begin
  Result := CheckRepoStatusLocalFirst(aRepoRoot, aMatched, aCache, aTtlSeconds, aQueue,
    aStatus, lFetchSkippedByCache, lFetchAttempted);
end;

function TRepoScanner.CheckRepoStatusLocalFirst(const aRepoRoot: string;
  const aMatched: TArray<string>; const aCache: TRepoCache; const aTtlSeconds: Integer;
  const aQueue: TUiEventQueue; out aStatus: TRepoStatus;
  out aFetchSkippedByCache, aFetchAttempted: Boolean): Boolean;
var
  lEvent: TUiEvent;
  lFetchPlan: TRepoFetchPlan;
begin
  aFetchSkippedByCache := False;
  aFetchAttempted := False;
  Result := BuildLocalRepoStatus(aRepoRoot, aMatched, aCache, aTtlSeconds, aStatus, lFetchPlan);
  if not Result then
    Exit;
  aFetchSkippedByCache := lFetchPlan.CacheHit and not lFetchPlan.NeedsFetch;
  aFetchAttempted := lFetchPlan.NeedsFetch;
  lEvent := NewUiEvent(TUiEventKind.uekRepoResult);
  lEvent.RepoStatus := aStatus;
  aQueue.Enqueue(lEvent);
  if not lFetchPlan.NeedsFetch then
    Exit;
  Result := RefreshRepoStatus(aRepoRoot, aMatched, aCache, aTtlSeconds, lFetchPlan, aStatus);
  if not Result then
    Exit;
  lEvent := NewUiEvent(TUiEventKind.uekRepoResult);
  lEvent.RepoStatus := aStatus;
  aQueue.Enqueue(lEvent);
end;

function TRepoScanner.ExecuteScan(const aSettings: TAppSettings; const aQueue: TUiEventQueue;
  const aCancelToken: iCancelToken; const aGeneration: Int64): TScanSummary;
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
  lScanPath: string;
  lCachePath: string;
  lFingerprint: string;
  lIgnoreContent: string;
  lCachedCount: Integer;
  lPhaseSw: TStopwatch;
  lFetchCacheSkips: Integer;
  lFetchAttempts: Integer;
begin
  Result := default(TScanSummary);
  fQueue := aQueue;
  fCancelToken := aCancelToken;
  fGeneration := aGeneration;
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
    for lScanPath in aSettings.ScanPaths do
      LogDebug('ScanPath: ' + lScanPath);
    LogDebug('FilterPattern: ' + aSettings.TargetRepoName);
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
  if FileExists(lIgnorePath) then
    lIgnoreContent := TFile.ReadAllText(lIgnorePath, TEncoding.UTF8)
  else
    lIgnoreContent := '';
  lFingerprint := TRepoCache.BuildScanFingerprint(aSettings.ScanPaths, aSettings.TargetRepoName,
    aSettings.MaxDepth, lIgnoreContent);
  LogLine(cLogIgnoreFile + lIgnorePath);
  LogLine(cLogIgnoreLoaded + IntToStr(length(lIgnorePatterns)));

  lEvent := NewUiEvent(TUiEventKind.uekProgressStart);
  lEvent.ProgressMode := TProgressMode.pmIndeterminate;
  fQueue.Enqueue(lEvent);

  gc(lCache, TRepoCache.Create, g);
  try
    lCachePath := CombinePath([lSettingsFolder, 'repo-scan-cache.json']);
    if not lCache.LoadFromFile(lCachePath, lCacheErr) then
      LogLine(cLogCacheLoadFailed + lCacheErr, TLogType.Warning);
    lCachedCount := PublishCachedInventory(lCache, lFingerprint, fQueue);
    LogLine(Format(cLogCachedInventory, [lCachedCount]));

    LogLine(cLogPhase1);
    lPhaseSw := TStopwatch.StartNew;
    lCandidates := FindRepoCandidates(aSettings.ScanPaths, aSettings.TargetRepoName, aSettings.MaxDepth,
      lIgnorePatterns, lSkipped, fQueue);
    LogLine(Format(cLogPhaseComplete, [cLogPhase1, lPhaseSw.ElapsedMilliseconds]));
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

    lRepoRoots := lCandidates;
      LogLine(cLogRepoRoots + IntToStr(Length(lRepoRoots)));
      if Result.SkippedDueToCap then
        LogLine(cLogCapHit);

      if IsCancelled then
      begin
        PublishScanFinished(cLogSummary + ': cancelled');
        exit;
      end;

      LogLine(cLogPhase3);
      lPhaseSw := TStopwatch.StartNew;

      gc(lResults, TList<TRepoStatus>.Create, g);
      gc(lLock, TCriticalSection.Create, g);
      gc(lCacheLock, TCriticalSection.Create, g);
      fCacheLock := lCacheLock;

      lTaskCount := length(lRepoRoots);
      SetLength(lTasks, lTaskCount);
      for lIndex := 0 to lTaskCount - 1 do
      begin
        lTasks[lIndex].RepoRoot := lRepoRoots[lIndex];
        lTasks[lIndex].Matched := [lRepoRoots[lIndex]];
      end;

      lEvent := NewUiEvent(TUiEventKind.uekProgressStart);
      lEvent.ProgressMode := TProgressMode.pmDeterminate;
      lEvent.ProgressMax := lTaskCount;
      lEvent.ProgressValue := 0;
      fQueue.Enqueue(lEvent);

      lDone := 0;
      lFetchCacheSkips := 0;
      lFetchAttempts := 0;
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
            lLocalFetchAttempted: Boolean;
            lLocalFetchSkipped: Boolean;
          begin
            if IsCancelled then
              exit;

            LogLine(cLogPhase3Repo + lTasks[aIndex].RepoRoot);

            if CheckRepoStatusLocalFirst(lTasks[aIndex].RepoRoot, lTasks[aIndex].Matched,
              lCache, aSettings.CacheTtlSeconds, fQueue, lLocalStatus,
              lLocalFetchSkipped, lLocalFetchAttempted) then
            begin
              if lLocalFetchSkipped then
                TInterlocked.Increment(lFetchCacheSkips);
              if lLocalFetchAttempted then
                TInterlocked.Increment(lFetchAttempts);
              if IsCancelled then
                exit;
              lLock.Enter;
              try
                lResults.Add(lLocalStatus);
              finally
                lLock.Leave;
              end;

            end;

            if IsCancelled then
              exit;

            lLocalDone := TInterlocked.Increment(lDone);
            lLocalEvent := NewUiEvent(TUiEventKind.uekProgressUpdate);
            lLocalEvent.ProgressValue := lLocalDone;
            fQueue.Enqueue(lLocalEvent);

            if (lLocalDone mod 100 = 0) or (lLocalDone = lTaskCount) then
              LogDebug(Format(cLogPhase3Progress, [lLocalDone, lTaskCount]));
          end,
          lPool);
      end else begin
        lEvent := NewUiEvent(TUiEventKind.uekProgressUpdate);
        lEvent.ProgressValue := 0;
        fQueue.Enqueue(lEvent);
      end;

      LogLine(Format(cLogPhaseComplete, [cLogPhase3, lPhaseSw.ElapsedMilliseconds]));
      LogLine(Format(cLogFetchCache, [lFetchCacheSkips, lFetchAttempts]));

      if IsCancelled then
      begin
        PublishScanFinished(cLogSummary + ': cancelled');
        exit;
      end;

      SetLength(lRepoRoots, lResults.Count);
      for lIndex := 0 to lResults.Count - 1 do
        lRepoRoots[lIndex] := lResults[lIndex].RepoRoot;
      Result.RepoCount := Length(lRepoRoots);
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

      lEvent := NewUiEvent(TUiEventKind.uekProgressEnd);
      fQueue.Enqueue(lEvent);

      lCache.SetInventory(lFingerprint, lRepoRoots);
      if not lCache.SaveToFile(lCachePath, aSettings.CacheTtlSeconds, lCacheErr) then
        LogLine(cLogCacheSaveFailed + lCacheErr, TLogType.Warning)
      else
        LogLine(cLogCacheSaved);

      LogLine(Format(cLogQueuePeak, [fQueue.PeakCount]));

      lEvent := NewUiEvent(TUiEventKind.uekScanFinished);
      lEvent.Text := Format('%s: %d repos, %d needs attention, %d clean, %d candidates in %d ms',
        [cLogSummary, Result.RepoCount, Result.ProblemCount, Result.CleanCount, Result.CandidateCount,
          lSw.ElapsedMilliseconds]);
      fQueue.Enqueue(lEvent);
      Result.ElapsedMs := lSw.ElapsedMilliseconds;
  finally
    fCacheLock := nil;
    fLogger := nil;
  end;
end;

function TRepoScanner.ExecuteScan(const aSettings: TAppSettings; const aQueue: TUiEventQueue;
  const aCancelToken: iCancelToken): TScanSummary;
begin
  Result := ExecuteScan(aSettings, aQueue, aCancelToken, 0);
end;

end.
