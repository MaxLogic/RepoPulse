unit URepoScanner;

interface

uses
  System.Classes, System.DateUtils, System.diagnostics, System.generics.collections, System.IOUtils,
  System.SyncObjs, System.SysUtils, System.Threading,

  Winapi.Windows,

  AutoFree, CancelToken, maxLogic.Logger, maxLogic.IOUtils, maxLogic.StrUtils,
  UAppSettings, UFolderSelection, UGitClient, UModels, UPathRules, URepoCache, UUiEventQueue;

type
  TRepoDiscoveryRequest = record
    Roots: TArray<string>;
    Rules: TArray<TFolderSelectionRule>;
    UsePathSelection: Boolean;
    MaxDepth: Integer;
    IgnorePatterns: TArray<TIgnorePattern>;
    CacheTtlSeconds: Integer;
    DebugLogEnabled: Boolean;
  end;

  TRepoAnalysisRequest = record
    RepoRoots: TArray<string>;
    CacheTtlSeconds: Integer;
    ThrottleLimit: Integer;
    DebugLogEnabled: Boolean;
  end;

  TRepoOperationResult = record
    Summary: TScanSummary;
    Succeeded: Boolean;
    Cancelled: Boolean;
    Error: string;
    RepoRoots: TArray<string>;
  end;

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
    fCache: TRepoCache;
    fCachePath: string;
    fOwnsCache: Boolean;
    fCancelToken: iCancelToken;
    fDebugEnabled: Boolean;
    fLogger: iMaxLog;
    procedure LogDebug(const aText: string);
    procedure StoreAnalysisResult(const aCache: TRepoCache; var aStatus: TRepoStatus);
    function IsCancelled: boolean;
    function OperationCachePath: string;
  protected
    fGeneration: Int64;
    function NewUiEvent(const aKind: TUiEventKind): TUiEvent; virtual;
    function DiscoveryCandidateLimit: Integer; virtual;
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
      out aStatus: TRepoStatus; out aFetchSkippedByCache, aFetchAttempted: Boolean): Boolean; overload; virtual;
  public
    constructor Create(const aGit: TGitClient; const aCache: TRepoCache = nil;
      const aCachePath: string = '');
    destructor Destroy; override;
    property Cache: TRepoCache read fCache;
    function DiscoverRepositories(const aRequest: TRepoDiscoveryRequest; const aQueue: TUiEventQueue;
      const aCancelToken: iCancelToken; const aGeneration: Int64): TRepoOperationResult;
    function AnalyzeRepositories(const aRequest: TRepoAnalysisRequest; const aQueue: TUiEventQueue;
      const aCancelToken: iCancelToken; const aGeneration: Int64): TRepoOperationResult;
    function TryRefreshRepoStatus(const aSettings: TAppSettings; const aRepoRoot: string;
      const aMatched: TArray<string>; out aStatus: TRepoStatus; out aError: string): Boolean;
  end;

implementation

const
  cMaxGitProbeCandidates = 10000;
  cFetchTimeoutMs = 60000;
  cLogCacheSaveFailed = 'Cache save failed: ';
  cLogCapHit = 'Hit MaxGitProbeCandidates cap; scan truncated.';

resourcestring
  rsFetchSkippedNotWritable = 'skipped fetch (git dir not writable)';
  rsGitStatusFailed = 'Git status could not be read.';
  rsNotGitWorkTree = 'The repository is not a Git work tree.';

type
  TDirItem = record
    Path: string;
    Depth: integer;
  end;

constructor TRepoScanner.Create(const aGit: TGitClient; const aCache: TRepoCache;
  const aCachePath: string);
begin
  inherited Create;
  fGit := aGit;
  fCache := aCache;
  fOwnsCache := fCache = nil;
  if fOwnsCache then
    fCache := TRepoCache.Create;
  fCachePath := aCachePath;
end;

destructor TRepoScanner.Destroy;
begin
  if fOwnsCache then
    fCache.Free;
  inherited;
end;

function TRepoScanner.TryRefreshRepoStatus(const aSettings: TAppSettings; const aRepoRoot: string;
  const aMatched: TArray<string>; out aStatus: TRepoStatus; out aError: string): Boolean;
var
  lCache: TRepoCache;
  lCacheErr: string;
  lSettingsFolder: string;
  lCachePath: string;
begin
  aStatus := Default(TRepoStatus);
  aStatus.RepoRoot := aRepoRoot;
  aStatus.MatchedFolders := aMatched;
  aError := '';
  Result := False;

  fCancelToken := nil;
  fDebugEnabled := aSettings.DebugLogEnabled;
  fLogger := maxLog.CloneWithTag('RepoScanner');
  try
    lSettingsFolder := TAppSettings.GetSettingsFolder;
    if not DirectoryExists(lSettingsFolder) then
      ForceDirectories(lSettingsFolder);

    lCachePath := fCachePath;
    if lCachePath = '' then
      lCachePath := CombinePath([lSettingsFolder, 'repo-scan-cache.json']);
    lCache := fCache;
    if not lCache.EnsureLoaded(lCachePath, lCacheErr) then
      aError := lCacheErr;

    if not BuildRepoStatus(aRepoRoot, aMatched, lCache, aSettings.CacheTtlSeconds, aStatus) then
    begin
      if aStatus.ScanError <> '' then
        aError := aStatus.ScanError;
      if aError = '' then
        aError := rsGitStatusFailed;
      lCache.StoreStatus(aStatus, '');
      lCache.TryGetStatus(aRepoRoot, aStatus);
      if not lCache.SaveToFile(lCachePath, aSettings.CacheTtlSeconds, lCacheErr) then
        aError := aError + sLineBreak + lCacheErr;
      Exit(False);
    end;

    aStatus.LastAnalyzedUtc := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
    aStatus.IsCached := False;
    lCache.StoreStatus(aStatus, aStatus.LastAnalyzedUtc);
    if aStatus.CacheUpdate.Key <> '' then
      lCache.ApplyUpdate(aStatus.CacheUpdate);
    if not lCache.SaveToFile(lCachePath, aSettings.CacheTtlSeconds, lCacheErr) then
    begin
      if aError <> '' then
        aError := aError + sLineBreak;
      aError := aError + cLogCacheSaveFailed + lCacheErr;
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

function TRepoScanner.IsCancelled: boolean;
begin
  if fCancelToken = nil then
    exit(False);
  Result := fCancelToken.Canceled;
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
  lUnrelatedHistory: Boolean;
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
  lMergeBaseRes: TGitResult;
begin
  aStatus := default(TRepoStatus);
  aStatus.RepoRoot := aRepoRoot;
  aStatus.MatchedFolders := aMatched;
  aStatus.Branch := rsBranchUnknown;
  aFetchPlan := Default(TRepoFetchPlan);

  if IsCancelled then
    exit(False);

  LogDebug('Repo start: ' + aRepoRoot);

  if not fGit.TryIsInsideWorkTree(aRepoRoot, lIsInside, lErr) then
  begin
    aStatus.ScanFailed := True;
    aStatus.ScanError := Trim(lErr);
    if aStatus.ScanError = '' then
      aStatus.ScanError := rsGitStatusFailed;
    aStatus.HasProblem := True;
    exit(False);
  end;
  if not lIsInside then
  begin
    aStatus.ScanFailed := True;
    aStatus.ScanError := rsNotGitWorkTree;
    aStatus.HasProblem := True;
    exit(False);
  end;

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
      aFetchPlan.CacheHit := aCache.TryGet(aRepoRoot.ToLowerInvariant, lCacheEntry);
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
  begin
    aStatus.ScanFailed := True;
    aStatus.ScanError := Trim(lErr);
    if aStatus.ScanError = '' then
      aStatus.ScanError := rsGitStatusFailed;
    aStatus.HasProblem := True;
    Exit(False);
  end;
  lParse := TGitClient.ParseStatusPorcelain(lStatusLines);

  lAhead := 0;
  lBehind := 0;
  lUnrelatedHistory := False;
  lCanCompare := lHasRemote and (lUpstream <> '');
  if lCanCompare then
  begin
    if IsCancelled then
      exit(False);
    fGit.TryGetAheadBehind(aRepoRoot, lUpstream, lAhead, lBehind, lErr);
    if (lAhead > 0) and (lBehind > 0) and
      fGit.TryRunGit(aRepoRoot, ['merge-base', 'HEAD', lUpstream], lMergeBaseRes, lErr, 0) then
      lUnrelatedHistory := lMergeBaseRes.ExitCode = 1;
  end;

  if lUnrelatedHistory then
  begin
    lAhead := 0;
    lBehind := 0;
  end;

  aStatus.RepoRoot := aRepoRoot;
  aStatus.MatchedFolders := aMatched;
  aStatus.Branch := lBranch;
  aStatus.IsSubmodule := lIsSubmodule;
  aStatus.SuperprojectRoot := lSuperprojectRoot;
  aStatus.SubmoduleMainRemoteRef := lSubmoduleMainRef;
  aStatus.SubmoduleNeedsMainFastForward := lShouldCheckMainFastForward and
    (not lCanFastForwardToMain) and (not lUnrelatedHistory);
  aStatus.HasOrigin := lHasRemote;
  aStatus.Upstream := lUpstream;
  aStatus.CanCompare := lCanCompare;
  aStatus.UnrelatedHistory := lUnrelatedHistory;
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
    aStatus.SubmoduleNeedsMainFastForward or aStatus.UnrelatedHistory;

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
    begin
      aStatus := lRefreshedStatus;
      Exit(False);
    end;
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

procedure TRepoScanner.StoreAnalysisResult(const aCache: TRepoCache; var aStatus: TRepoStatus);
var
  lStored: TRepoStatus;
begin
  if not aStatus.ScanFailed then
  begin
    aStatus.LastAnalyzedUtc := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
    aStatus.IsCached := False;
  end;
  aCache.StoreStatus(aStatus, aStatus.LastAnalyzedUtc);
  if aStatus.CacheUpdate.Key <> '' then
    aCache.ApplyUpdate(aStatus.CacheUpdate);
  if aStatus.ScanFailed and aCache.TryGetStatus(aStatus.RepoRoot, lStored) then
    aStatus := lStored;
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
  begin
    if IsCancelled then
      Exit;
    StoreAnalysisResult(aCache, aStatus);
    lEvent := NewUiEvent(TUiEventKind.uekRepoResult);
    lEvent.RepoStatus := aStatus;
    aQueue.Enqueue(lEvent);
    Exit(True);
  end;
  aFetchSkippedByCache := lFetchPlan.CacheHit and not lFetchPlan.NeedsFetch;
  aFetchAttempted := lFetchPlan.NeedsFetch;
  StoreAnalysisResult(aCache, aStatus);
  lEvent := NewUiEvent(TUiEventKind.uekRepoResult);
  lEvent.RepoStatus := aStatus;
  aQueue.Enqueue(lEvent);
  if not lFetchPlan.NeedsFetch then
    Exit;
  Result := RefreshRepoStatus(aRepoRoot, aMatched, aCache, aTtlSeconds, lFetchPlan, aStatus);
  if not Result then
  begin
    if IsCancelled then
      Exit;
    StoreAnalysisResult(aCache, aStatus);
    lEvent := NewUiEvent(TUiEventKind.uekRepoResult);
    lEvent.RepoStatus := aStatus;
    aQueue.Enqueue(lEvent);
    Exit(True);
  end;
  StoreAnalysisResult(aCache, aStatus);
  lEvent := NewUiEvent(TUiEventKind.uekRepoResult);
  lEvent.RepoStatus := aStatus;
  aQueue.Enqueue(lEvent);
end;

function TRepoScanner.OperationCachePath: string;
begin
  Result := fCachePath;
  if Result = '' then
    Result := TPath.Combine(TAppSettings.GetSettingsFolder, 'repo-scan-cache.json');
end;

function TRepoScanner.DiscoveryCandidateLimit: Integer;
begin
  Result := cMaxGitProbeCandidates;
end;

function TRepoScanner.DiscoverRepositories(const aRequest: TRepoDiscoveryRequest;
  const aQueue: TUiEventQueue; const aCancelToken: iCancelToken;
  const aGeneration: Int64): TRepoOperationResult;
var
  g: TGarbos;
  lRequest: TRepoDiscoveryRequest;
  lPending: TQueue<TDirItem>;
  lFound: TList<string>;
  lSeen: TDictionary<string, Boolean>;
  lVisited: TDictionary<string, Integer>;
  lRoot, lRootNorm, lCachePath, lEntryName: string;
  lItem, lChild: TDirItem;
  lRule: TFolderSelectionRule;
  lRoots: TList<string>;
  lFindData: TWin32FindData;
  lFindHandle: THandle;
  lFindError: Cardinal;
  lAttributes: Cardinal;
  lRemaining: Integer;
  lEvent: TUiEvent;
  lSw: TStopwatch;
begin
  Result := Default(TRepoOperationResult);
  lSw := TStopwatch.StartNew;
  lRequest := aRequest;
  lRequest.Roots := Copy(aRequest.Roots);
  lRequest.Rules := Copy(aRequest.Rules);
  lRequest.IgnorePatterns := Copy(aRequest.IgnorePatterns);
  fCancelToken := aCancelToken;
  fGeneration := aGeneration;
  fDebugEnabled := lRequest.DebugLogEnabled;
  fLogger := maxLog.CloneWithTag('RepoDiscovery');
  lCachePath := OperationCachePath;
  try
    try
      if not fCache.EnsureLoaded(lCachePath, Result.Error) then
        Exit;
      GC(lPending, TQueue<TDirItem>.Create, g);
      GC(lFound, TList<string>.Create, g);
      GC(lRoots, TList<string>.Create, g);
      GC(lSeen, TDictionary<string, Boolean>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase), g);
      GC(lVisited, TDictionary<string, Integer>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase), g);
      lRoots.AddRange(lRequest.Roots);
      // Deeper explicit inclusions remain reachable beneath excluded parents.
      if lRequest.UsePathSelection then
        for lRule in lRequest.Rules do
          if lRule.Included then
            lRoots.Add(lRule.Path);
      for lRoot in lRoots do
      begin
        if IsCancelled then
          Break;
        if Trim(lRoot) = '' then
          Continue;
        lItem.Path := NormalizeSelectionPath(lRoot);
        lItem.Depth := 0;
        lRootNorm := NormalizePathForMatch(lItem.Path);
        lPending.Enqueue(lItem);
        // Ignore rules are relative to each captured search scope.
        lVisited.Clear;
        while (lPending.Count > 0) and not IsCancelled do
        begin
          lItem := lPending.Dequeue;
          if lVisited.TryGetValue(lItem.Path, lRemaining) and (lRemaining <= lItem.Depth) then
            Continue;
          lVisited.AddOrSetValue(lItem.Path, lItem.Depth);
          if ShouldIgnoreDirectory(lItem.Path, lRootNorm, lRequest.IgnorePatterns) then
            Continue;
          // Explicit deeper inclusions are separate roots; unchecked branches need no traversal.
          if lRequest.UsePathSelection and not EvaluateFolderSelection(lItem.Path, lRequest.Rules) then
            Continue;
          lAttributes := GetFileAttributes(PChar(lItem.Path));
          if (lAttributes = INVALID_FILE_ATTRIBUTES) or
            ((lAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0) then
          begin
            Result.Error := 'Discovery could not access directory: ' + lItem.Path;
            Exit;
          end;
          if (lAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
            Continue;
          if (DirectoryExists(TPath.Combine(lItem.Path, '.git')) or
              FileExists(TPath.Combine(lItem.Path, '.git'))) and not lSeen.ContainsKey(lItem.Path) then
          begin
            lSeen.Add(lItem.Path, True);
            lFound.Add(lItem.Path);
            Result.Summary.DiscoveredCount := lFound.Count;
            lEvent := NewUiEvent(TUiEventKind.uekDiscoveryFound);
            lEvent.RepoRoot := lItem.Path;
            aQueue.Enqueue(lEvent);
            if lFound.Count >= DiscoveryCandidateLimit then
            begin
              Result.Summary.SkippedDueToCap := True;
              Result.Error := cLogCapHit;
              Exit;
            end;
          end;
          if lItem.Depth >= lRequest.MaxDepth then
            Continue;
          // RTL GetDirectories silently treats native errors as empty directories.
          lFindHandle := Winapi.Windows.FindFirstFile(PChar(TPath.Combine(lItem.Path, '*')), lFindData);
          if lFindHandle = INVALID_HANDLE_VALUE then
          begin
            lFindError := GetLastError;
            if lFindError = ERROR_FILE_NOT_FOUND then
              Continue;
            raise EOSError.CreateFmt('Discovery could not enumerate %s: %s (%d)',
              [lItem.Path, SysErrorMessage(lFindError), lFindError]);
          end;
          try
            repeat
              lEntryName := lFindData.cFileName;
              if ((lFindData.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) and
                (lEntryName <> '.') and (lEntryName <> '..') and not SameText(lEntryName, '.git') then
              begin
                lChild.Path := NormalizeSelectionPath(TPath.Combine(lItem.Path, lEntryName));
                lChild.Depth := lItem.Depth + 1;
                lPending.Enqueue(lChild);
              end;
              if IsCancelled then
                Break;
              if not Winapi.Windows.FindNextFile(lFindHandle, lFindData) then
              begin
                lFindError := GetLastError;
                if lFindError <> ERROR_NO_MORE_FILES then
                  raise EOSError.CreateFmt('Discovery could not finish enumerating %s: %s (%d)',
                    [lItem.Path, SysErrorMessage(lFindError), lFindError]);
                Break;
              end;
            until False;
          finally
            Winapi.Windows.FindClose(lFindHandle);
          end;
        end;
      end;
      if not IsCancelled then
        Result.Succeeded := fCache.TryCommitDiscoveredInventory(lFound.ToArray,
          lCachePath, lRequest.CacheTtlSeconds, Result.Error);
    except
      on E: Exception do
        Result.Error := E.Message;
    end;
  finally
    Result.Cancelled := IsCancelled and not Result.Succeeded;
    Result.RepoRoots := fCache.GetInventory;
    Result.Summary.CandidateCount := Result.Summary.DiscoveredCount;
    Result.Summary.RepoCount := Length(Result.RepoRoots);
    Result.Summary.ElapsedMs := lSw.ElapsedMilliseconds;
    lEvent := NewUiEvent(TUiEventKind.uekDiscoveryFinished);
    lEvent.OperationSucceeded := Result.Succeeded;
    lEvent.OperationCancelled := Result.Cancelled;
    lEvent.OperationError := Result.Error;
    lEvent.RepoRoots := Copy(Result.RepoRoots);
    lEvent.ScanSummary := Result.Summary;
    lEvent.HasScanSummary := True;
    aQueue.Enqueue(lEvent);
    fLogger := nil;
  end;
end;

function TRepoScanner.AnalyzeRepositories(const aRequest: TRepoAnalysisRequest;
  const aQueue: TUiEventQueue; const aCancelToken: iCancelToken;
  const aGeneration: Int64): TRepoOperationResult;
var
  g: TGarbos;
  lRequest: TRepoAnalysisRequest;
  lRoots: TList<string>;
  lSeen: TDictionary<string, Boolean>;
  lRoot, lCachePath, lError: string;
  lPool: TThreadPool;
  lLock: TCriticalSection;
  lResults: TList<TRepoStatus>;
  lStatus: TRepoStatus;
  lEvent: TUiEvent;
  lSw: TStopwatch;
  lDone, lWorkers: Integer;
begin
  Result := Default(TRepoOperationResult);
  lSw := TStopwatch.StartNew;
  lRequest := aRequest;
  lRequest.RepoRoots := Copy(aRequest.RepoRoots);
  fCancelToken := aCancelToken;
  fGeneration := aGeneration;
  fDebugEnabled := lRequest.DebugLogEnabled;
  fLogger := maxLog.CloneWithTag('RepoAnalysis');
  lCachePath := OperationCachePath;
  GC(lResults, TList<TRepoStatus>.Create, g);
  try
    try
      if not fCache.EnsureLoaded(lCachePath, Result.Error) then
        Exit;
      GC(lRoots, TList<string>.Create, g);
      GC(lSeen, TDictionary<string, Boolean>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase), g);
      for lRoot in lRequest.RepoRoots do
        if (Trim(lRoot) <> '') and not lSeen.ContainsKey(lRoot) then
        begin
          lSeen.Add(lRoot, True);
          lRoots.Add(lRoot);
        end;
      lRequest.RepoRoots := lRoots.ToArray;
      Result.Summary.CandidateCount := Length(lRequest.RepoRoots);
      lEvent := NewUiEvent(TUiEventKind.uekProgressStart);
      lEvent.ProgressMode := TProgressMode.pmDeterminate;
      lEvent.ProgressMax := Length(lRequest.RepoRoots);
      aQueue.Enqueue(lEvent);
      lDone := 0;
      GC(lLock, TCriticalSection.Create, g);
      lWorkers := lRequest.ThrottleLimit;
      if lWorkers < 1 then
        lWorkers := 1;
      if Length(lRequest.RepoRoots) > 0 then
      begin
        GC(lPool, TThreadPool.Create, g);
        lPool.UnlimitedWorkerThreadsWhenBlocked := False;
        lPool.SetMaxWorkerThreads(lWorkers);
        lPool.SetMinWorkerThreads(lWorkers);
        TParallel.For(0, High(lRequest.RepoRoots),
          procedure(aIndex: Integer)
          var
            lStatus: TRepoStatus;
            lEvent: TUiEvent;
            lSkipped, lFetched: Boolean;
          begin
            if IsCancelled then
              Exit;
            if CheckRepoStatusLocalFirst(lRequest.RepoRoots[aIndex], [lRequest.RepoRoots[aIndex]],
              fCache, lRequest.CacheTtlSeconds, aQueue, lStatus, lSkipped, lFetched) then
            begin
              lLock.Enter;
              try
                lResults.Add(lStatus);
              finally
                lLock.Leave;
              end;
            end;
            lEvent := NewUiEvent(TUiEventKind.uekProgressUpdate);
            lEvent.ProgressValue := TInterlocked.Increment(lDone);
            aQueue.Enqueue(lEvent);
          end, lPool);
      end;
      Result.Succeeded := not IsCancelled;
    except
      on E: Exception do
        Result.Error := E.Message;
    end;
  finally
    if not fCache.FlushPending(lCachePath, lRequest.CacheTtlSeconds, lError) then
    begin
      Result.Succeeded := False;
      if Result.Error <> '' then
        Result.Error := Result.Error + sLineBreak;
      Result.Error := Result.Error + lError;
    end;
    Result.Cancelled := IsCancelled;
    Result.RepoRoots := fCache.GetInventory;
    Result.Summary.RepoCount := lResults.Count;
    for lStatus in lResults do
      if lStatus.HasProblem then
        Inc(Result.Summary.ProblemCount)
      else
        Inc(Result.Summary.CleanCount);
    Result.Summary.ElapsedMs := lSw.ElapsedMilliseconds;
    lEvent := NewUiEvent(TUiEventKind.uekAnalysisFinished);
    lEvent.OperationSucceeded := Result.Succeeded;
    lEvent.OperationCancelled := Result.Cancelled;
    lEvent.OperationError := Result.Error;
    lEvent.RepoRoots := Copy(Result.RepoRoots);
    lEvent.ScanSummary := Result.Summary;
    lEvent.HasScanSummary := True;
    aQueue.Enqueue(lEvent);
    fLogger := nil;
  end;
end;

end.
