unit TestGitParsing;

interface

uses
  System.Classes, System.DateUtils, System.IOUtils, System.SysUtils,

  AutoFree, CancelToken, DUnitX.TestFramework,
  UAppSettings, UGitClient, UModels, URepoCache, URepoScanner, UUiEventQueue;

type
  [TestFixture]
  TGitParsingTests = class
  private
    procedure RunGit(const aGit: TGitClient; const aRepo: string; const aArgs: TArray<string>);
  public
    [Test]
    procedure Analyze_VisitsOnlyExplicitRootsAndPreservesMembership;
    [Test]
    procedure Analyze_EmptyScopeStartsNoGitAndReportsFailedPendingSave;
    [Test]
    procedure ParseStatusPorcelain_StagedAndUnstaged;
    [Test]
    procedure RefreshStatus_PersistsObservationThroughSharedCache;
    [Test]
    procedure RefreshStatus_FailureRetainsLastObservationAndPersistsError;
    [Test]
    procedure Analyze_CancelAfterCompletedResultFlushesSharedCache;
    [Test]
    procedure Discovery_CancelThenAnalyzePreservesCommittedMembershipOnRestart;
    [Test]
    procedure ParseAheadBehind_Basic;
    [Test]
    procedure IsPullConflictError_DetectsFastForwardAbort;
    [Test]
    procedure IsPullConflictError_IgnoresNetworkFailures;
    [Test]
    procedure LocalFirstStatus_QueuesBeforeAndAfterStaleFetch;
    [Test]
    procedure LocalFirstStatus_FreshCacheQueuesOnceWithoutFetch;
    [Test]
    procedure LocalFirstStatus_CorruptIndexPublishesFailureAndRecovers;
    [Test]
    procedure RefreshStatus_RegularRepoAheadOfOriginNeedsMainFastForward;
    [Test]
    procedure RefreshStatus_UnrelatedHistorySuppressesDirectionalState;
    [Test]
    procedure Pull_DetachedSubmoduleFastForwardsRemoteDefaultAndRemainsDetached;
    [Test]
    procedure ResolveSuperprojectRoot_RealSubmodule;
  end;

implementation

procedure TGitParsingTests.Analyze_EmptyScopeStartsNoGitAndReportsFailedPendingSave;
var
  g: TGarbos;
  lCache: TRepoCache;
  lScanner: TRepoScanner;
  lQueue: TUiEventQueue;
  lRequest: TRepoAnalysisRequest;
  lResult: TRepoOperationResult;
  lStatus: TRepoStatus;
  lEvent: TUiEvent;
  lLock: TFileStream;
  lRoot, lPath, lError: string;
  lTerminals: Integer;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseEmptyAnalyze-' + TPath.GetRandomFileName);
  ForceDirectories(lRoot);
  lPath := TPath.Combine(lRoot, 'cache.json');
  try
    GC(lCache, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);
    Assert.IsTrue(lCache.EnsureLoaded(lPath, lError), lError);
    lCache.SetInventory('', ['Z:\committed']);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    GC(lScanner, TRepoScanner.Create(nil, lCache, lPath), g);
    lRequest := Default(TRepoAnalysisRequest);
    lRequest.CacheTtlSeconds := 3600;
    lResult := lScanner.AnalyzeRepositories(lRequest, lQueue, nil, 51);
    Assert.IsTrue(lResult.Succeeded, lResult.Error);
    Assert.AreEqual(0, lResult.Summary.RepoCount);
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := 'Z:\committed';
    lCache.StoreStatus(lStatus, '2026-09-20T01:00:00.000Z');
    lLock := TFileStream.Create(lPath, fmOpenRead or fmShareDenyWrite);
    try
      lResult := lScanner.AnalyzeRepositories(lRequest, lQueue, nil, 52);
      Assert.IsFalse(lResult.Succeeded);
      Assert.IsNotEmpty(lResult.Error);
      Assert.AreEqual(1, Length(lResult.RepoRoots));
    finally
      lLock.Free;
    end;
    lTerminals := 0;
    while lQueue.TryDequeue(lEvent) do
    begin
      Assert.IsFalse(lEvent.Kind = TUiEventKind.uekRepoResult);
      if lEvent.Kind = TUiEventKind.uekAnalysisFinished then
      begin
        Inc(lTerminals);
        if lEvent.Generation = 52 then
        begin
          Assert.IsFalse(lEvent.OperationSucceeded);
          Assert.IsNotEmpty(lEvent.OperationError);
        end;
      end;
    end;
    Assert.AreEqual(2, lTerminals);
    Assert.IsTrue(lCache.FlushPending(lPath, 3600, lError), lError);
  finally
    g.Clear;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TGitParsingTests.Analyze_VisitsOnlyExplicitRootsAndPreservesMembership;
var
  g: TGarbos;
  lGit: TGitClient;
  lScanner: TRepoScanner;
  lCache, lReloaded: TRepoCache;
  lQueue: TUiEventQueue;
  lRequest: TRepoAnalysisRequest;
  lResult: TRepoOperationResult;
  lStatus: TRepoStatus;
  lEvent: TUiEvent;
  lRoot, lRepo, lHidden, lPath, lError: string;
  lFinished: Integer;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseAnalyze-' + TPath.GetRandomFileName);
  lRepo := TPath.Combine(lRoot, 'selected');
  lHidden := TPath.Combine(lRoot, 'hidden');
  lPath := TPath.Combine(lRoot, 'cache.json');
  ForceDirectories(lRepo);
  try
    GC(lGit, TGitClient.Create, g);
    RunGit(lGit, lRepo, ['init', '--initial-branch=main']);
    RunGit(lGit, lRepo, ['-c', 'user.name=RepoPulse Test', '-c',
      'user.email=repopulse@example.invalid', 'commit', '--allow-empty', '-m', 'fixture']);
    GC(lCache, TRepoCache.Create, g);
    GC(lReloaded, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);
    Assert.IsTrue(lCache.EnsureLoaded(lPath, lError), lError);
    lCache.SetInventory('', [lRepo, lHidden]);
    GC(lScanner, TRepoScanner.Create(lGit, lCache, lPath), g);
    lRequest := Default(TRepoAnalysisRequest);
    lRequest.RepoRoots := [lRepo];
    lRequest.ThrottleLimit := 1;
    lRequest.CacheTtlSeconds := 3600;
    lResult := lScanner.AnalyzeRepositories(lRequest, lQueue, nil, 42);
    Assert.IsTrue(lResult.Succeeded, lResult.Error);
    Assert.AreEqual(1, lResult.Summary.RepoCount);
    Assert.IsTrue(lCache.TryGetStatus(lRepo, lStatus));
    Assert.AreEqual('main', lStatus.Branch);
    Assert.IsNotEmpty(lStatus.LastAnalyzedUtc);
    Assert.IsFalse(lCache.TryGetStatus(lHidden, lStatus));
    Assert.IsTrue(lReloaded.LoadFromFile(lPath, lError), lError);
    Assert.AreEqual(2, Length(lReloaded.GetInventory));
    lFinished := 0;
    while lQueue.TryDequeue(lEvent) do
    begin
      Assert.AreEqual(Int64(42), lEvent.Generation);
      Assert.IsFalse(lEvent.Kind = TUiEventKind.uekDiscoveryFound);
      if lEvent.Kind = TUiEventKind.uekRepoResult then
        Assert.AreEqual(lRepo, lEvent.RepoStatus.RepoRoot);
      if lEvent.Kind = TUiEventKind.uekAnalysisFinished then
      begin
        Inc(lFinished);
        Assert.IsTrue(lEvent.OperationSucceeded);
      end;
    end;
    Assert.AreEqual(1, lFinished);
  finally
    g.Clear;
    TDirectory.Delete(lRoot, True);
  end;
end;

type
  TTestRepoScanner = class(TRepoScanner)
  protected
    function NewUiEvent(const aKind: TUiEventKind): TUiEvent; override;
    function CheckRepoStatusLocalFirst(const aRepoRoot: string; const aMatched: TArray<string>;
      const aCache: TRepoCache; const aTtlSeconds: Integer; const aQueue: TUiEventQueue;
      out aStatus: TRepoStatus; out aFetchSkippedByCache, aFetchAttempted: Boolean): Boolean; override;
  public
    CancelAfterResult: iCancelToken;
    CancelOnDiscovery: iCancelToken;
    function BuildStatus(const aRepoRoot: string; const aCache: TRepoCache; out aStatus: TRepoStatus): Boolean;
    function CheckLocalFirst(const aRepoRoot: string; const aCache: TRepoCache;
      const aQueue: TUiEventQueue; const aGeneration: Int64; out aStatus: TRepoStatus): Boolean;
  end;

function TTestRepoScanner.NewUiEvent(const aKind: TUiEventKind): TUiEvent;
begin
  Result := inherited NewUiEvent(aKind);
  // Cancel at a deterministic publication boundary, retaining real traversal and queue delivery.
  if (aKind = TUiEventKind.uekDiscoveryFound) and (CancelOnDiscovery <> nil) then
    CancelOnDiscovery.Cancel;
end;

function TTestRepoScanner.CheckRepoStatusLocalFirst(const aRepoRoot: string;
  const aMatched: TArray<string>; const aCache: TRepoCache; const aTtlSeconds: Integer;
  const aQueue: TUiEventQueue; out aStatus: TRepoStatus;
  out aFetchSkippedByCache, aFetchAttempted: Boolean): Boolean;
begin
  Result := inherited CheckRepoStatusLocalFirst(aRepoRoot, aMatched, aCache,
    aTtlSeconds, aQueue, aStatus, aFetchSkippedByCache, aFetchAttempted);
  if Result and (CancelAfterResult <> nil) then
    CancelAfterResult.Cancel;
end;

function TTestRepoScanner.BuildStatus(const aRepoRoot: string; const aCache: TRepoCache;
  out aStatus: TRepoStatus): Boolean;
begin
  Result := BuildRepoStatus(aRepoRoot, [], aCache, 0, aStatus);
end;

function TTestRepoScanner.CheckLocalFirst(const aRepoRoot: string; const aCache: TRepoCache;
  const aQueue: TUiEventQueue; const aGeneration: Int64; out aStatus: TRepoStatus): Boolean;
begin
  fGeneration := aGeneration;
  Result := inherited CheckRepoStatusLocalFirst(aRepoRoot, [aRepoRoot], aCache, 3600, aQueue, aStatus);
end;

procedure TGitParsingTests.RunGit(const aGit: TGitClient; const aRepo: string;
  const aArgs: TArray<string>);
var
  lResult: TGitResult;
  lError: string;
begin
  Assert.IsTrue(aGit.TryRunGit(aRepo, aArgs, lResult, lError), lError);
  Assert.AreEqual(0, Integer(lResult.ExitCode), lResult.OutputText);
end;

procedure TGitParsingTests.RefreshStatus_PersistsObservationThroughSharedCache;
var
  g: TGarbos;
  lGit: TGitClient;
  lScanner: TRepoScanner;
  lCache, lReloaded: TRepoCache;
  lSettings: TAppSettings;
  lRoot, lRepo, lPath, lError: string;
  lStatus, lStored: TRepoStatus;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseShared-' + TPath.GetRandomFileName);
  lRepo := TPath.Combine(lRoot, 'repo');
  lPath := TPath.Combine(lRoot, 'cache.json');
  ForceDirectories(lRepo);
  try
    GC(lGit, TGitClient.Create, g);
    RunGit(lGit, lRepo, ['init', '--initial-branch=main']);
    RunGit(lGit, lRepo, ['-c', 'user.name=RepoPulse Test', '-c',
      'user.email=repopulse@example.invalid', 'commit', '--allow-empty', '-m', 'fixture']);
    GC(lSettings, TAppSettings.Create, g);
    GC(lCache, TRepoCache.Create, g);
    Assert.IsTrue(lCache.EnsureLoaded(lPath, lError), lError);
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := TPath.Combine(lRoot, 'pending');
    lStatus.Branch := 'pending-observation';
    lCache.StoreStatus(lStatus, '2026-09-19T10:00:00Z');
    GC(lScanner, TRepoScanner.Create(lGit, lCache, lPath), g);
    Assert.IsTrue(lScanner.TryRefreshRepoStatus(lSettings, lRepo, [lRepo], lStatus, lError), lError);
    Assert.IsTrue(lCache.TryGetStatus(lRepo, lStored), 'Public analysis must update the shared cache');
    Assert.AreEqual('main', lStored.Branch);
    Assert.IsTrue(lStored.LastAnalyzedUtc <> '', 'Successful observation needs UTC time');
    Assert.IsFalse(lStored.IsCached);
    GC(lReloaded, TRepoCache.Create, g);
    Assert.IsTrue(lReloaded.LoadFromFile(lPath, lError), lError);
    Assert.IsTrue(lReloaded.TryGetStatus(lRepo, lStored), 'Completed result must survive restart');
    Assert.IsTrue(lStored.IsCached);
    Assert.IsTrue(lReloaded.TryGetStatus(TPath.Combine(lRoot, 'pending'), lStored),
      'Analysis must retain pending observations from the shared cache');
    Assert.AreEqual('pending-observation', lStored.Branch);
  finally
    g.Clear;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TGitParsingTests.RefreshStatus_FailureRetainsLastObservationAndPersistsError;
var
  g: TGarbos;
  lGit: TGitClient;
  lScanner: TRepoScanner;
  lCache, lReloaded: TRepoCache;
  lSettings: TAppSettings;
  lRoot, lRepo, lPath, lError: string;
  lStatus, lStored: TRepoStatus;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseFailed-' + TPath.GetRandomFileName);
  lRepo := TPath.Combine(lRoot, 'unavailable-repo');
  lPath := TPath.Combine(lRoot, 'cache.json');
  ForceDirectories(lRoot);
  try
    GC(lGit, TGitClient.Create, g);
    GC(lSettings, TAppSettings.Create, g);
    GC(lCache, TRepoCache.Create, g);
    Assert.IsTrue(lCache.EnsureLoaded(lPath, lError), lError);
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := lRepo;
    lStatus.Branch := 'previous-main';
    lCache.StoreStatus(lStatus, '2026-09-19T10:00:00Z');
    Assert.IsTrue(lCache.SaveToFile(lPath, lSettings.CacheTtlSeconds, lError), lError);
    GC(lScanner, TRepoScanner.Create(lGit, lCache, lPath), g);
    Assert.IsFalse(lScanner.TryRefreshRepoStatus(lSettings, lRepo, [lRepo], lStatus, lError));
    Assert.IsTrue(lError <> '');
    Assert.IsTrue(lCache.TryGetStatus(lRepo, lStored));
    Assert.IsTrue(lStored.ScanFailed, 'Failed analysis must record the attempt error');
    Assert.IsTrue(lStored.ScanError <> '');
    Assert.AreEqual('previous-main', lStored.Branch);
    Assert.AreEqual('2026-09-19T10:00:00Z', lStored.LastAnalyzedUtc);
    Assert.AreEqual(lStored.Branch, lStatus.Branch, 'UI result must retain the last observation');
    Assert.AreEqual(lStored.LastAnalyzedUtc, lStatus.LastAnalyzedUtc);
    GC(lReloaded, TRepoCache.Create, g);
    Assert.IsTrue(lReloaded.LoadFromFile(lPath, lError), lError);
    Assert.IsTrue(lReloaded.TryGetStatus(lRepo, lStored));
    Assert.IsTrue(lStored.ScanFailed, 'Attempt error must survive restart');
    Assert.AreEqual('previous-main', lStored.Branch);
  finally
    g.Clear;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TGitParsingTests.Analyze_CancelAfterCompletedResultFlushesSharedCache;
var
  g: TGarbos;
  lGit: TGitClient;
  lScanner: TTestRepoScanner;
  lCache, lReloaded: TRepoCache;
  lRequest: TRepoAnalysisRequest;
  lQueue: TUiEventQueue;
  lCancel: iCancelToken;
  lRoot, lRepo, lPath, lError: string;
  lStatus: TRepoStatus;
  lInventory: TArray<string>;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseCancel-' + TPath.GetRandomFileName);
  lRepo := TPath.Combine(lRoot, 'repo');
  lPath := TPath.Combine(lRoot, 'cache.json');
  ForceDirectories(lRepo);
  try
    GC(lGit, TGitClient.Create, g);
    RunGit(lGit, lRepo, ['init', '--initial-branch=main']);
    RunGit(lGit, lRepo, ['-c', 'user.name=RepoPulse Test', '-c',
      'user.email=repopulse@example.invalid', 'commit', '--allow-empty', '-m', 'fixture']);
    lRequest := Default(TRepoAnalysisRequest);
    lRequest.RepoRoots := [lRepo];
    lRequest.ThrottleLimit := 1;
    lRequest.CacheTtlSeconds := 3600;
    GC(lQueue, TUiEventQueue.Create, g);
    GC(lCache, TRepoCache.Create, g);
    Assert.IsTrue(lCache.EnsureLoaded(lPath, lError), lError);
    lCache.SetInventory('committed-before-cancel', [lRepo, TPath.Combine(lRoot, 'unavailable')]);
    Assert.IsTrue(lCache.SaveToFile(lPath, lRequest.CacheTtlSeconds, lError), lError);
    lCancel := TCancelToken.Create;
    GC(lScanner, TTestRepoScanner.Create(lGit, lCache, lPath), g);
    lScanner.CancelAfterResult := lCancel;
    lScanner.AnalyzeRepositories(lRequest, lQueue, lCancel, 45);
    Assert.IsTrue(lCancel.Canceled, 'Fixture must cancel after the real completed result');
    Assert.IsTrue(lCache.TryGetStatus(lRepo, lStatus), 'Completed result must use the shared cache');
    Assert.AreEqual('main', lStatus.Branch);
    Assert.IsTrue(lStatus.LastAnalyzedUtc <> '');
    GC(lReloaded, TRepoCache.Create, g);
    Assert.IsTrue(lReloaded.LoadFromFile(lPath, lError), lError);
    Assert.IsTrue(lReloaded.TryGetStatus(lRepo, lStatus), 'Cancellation must flush completed results');
    Assert.AreEqual('main', lStatus.Branch);
    lInventory := lReloaded.GetInventory;
    Assert.AreEqual(2, Length(lInventory), 'Cancellation must not reconcile committed membership');
    Assert.AreEqual(lRepo, lInventory[0]);
    Assert.AreEqual(TPath.Combine(lRoot, 'unavailable'), lInventory[1]);
  finally
    g.Clear;
    lCancel := nil;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TGitParsingTests.Discovery_CancelThenAnalyzePreservesCommittedMembershipOnRestart;
var
  g: TGarbos;
  lGit: TGitClient;
  lScanner: TTestRepoScanner;
  lCache, lReloaded: TRepoCache;
  lQueue: TUiEventQueue;
  lDiscovery: TRepoDiscoveryRequest;
  lAnalysis: TRepoAnalysisRequest;
  lResult: TRepoOperationResult;
  lCancel: iCancelToken;
  lStatus: TRepoStatus;
  lEvent: TUiEvent;
  lRoot, lRepo, lNewRepo, lMissing, lPath, lError: string;
  lProvisional, lTerminal: Integer;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseDiscoveryCancel-' + TPath.GetRandomFileName);
  lRepo := TPath.Combine(lRoot, 'existing');
  lNewRepo := TPath.Combine(lRoot, 'new');
  lMissing := TPath.Combine(lRoot, 'unavailable');
  lPath := TPath.Combine(lRoot, 'cache.json');
  ForceDirectories(lRepo);
  ForceDirectories(TPath.Combine(lNewRepo, '.git'));
  try
    GC(lGit, TGitClient.Create, g);
    RunGit(lGit, lRepo, ['init', '--initial-branch=main']);
    RunGit(lGit, lRepo, ['-c', 'user.name=RepoPulse Test', '-c',
      'user.email=repopulse@example.invalid', 'commit', '--allow-empty', '-m', 'fixture']);
    GC(lCache, TRepoCache.Create, g);
    GC(lReloaded, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);
    Assert.IsTrue(lCache.EnsureLoaded(lPath, lError), lError);
    lCache.SetInventory('', [lRepo, lMissing]);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    GC(lScanner, TTestRepoScanner.Create(lGit, lCache, lPath), g);
    lCancel := TCancelToken.Create;
    lScanner.CancelOnDiscovery := lCancel;
    lDiscovery := Default(TRepoDiscoveryRequest);
    lDiscovery.Roots := [lNewRepo];
    lDiscovery.MaxDepth := 2;
    lDiscovery.CacheTtlSeconds := 3600;
    lResult := lScanner.DiscoverRepositories(lDiscovery, lQueue, lCancel, 46);
    Assert.IsTrue(lResult.Cancelled);
    Assert.IsFalse(lResult.Succeeded);
    Assert.AreEqual(2, Length(lResult.RepoRoots));
    lProvisional := 0;
    lTerminal := 0;
    while lQueue.TryDequeue(lEvent) do
    begin
      if lEvent.Kind = TUiEventKind.uekDiscoveryFound then
        Inc(lProvisional);
      if lEvent.Kind = TUiEventKind.uekDiscoveryFinished then
      begin
        Inc(lTerminal);
        Assert.IsTrue(lEvent.OperationCancelled);
        Assert.AreEqual(2, Length(lEvent.RepoRoots));
      end;
    end;
    Assert.AreEqual(1, lProvisional);
    Assert.AreEqual(1, lTerminal);
    lAnalysis := Default(TRepoAnalysisRequest);
    lAnalysis.RepoRoots := [lRepo];
    lAnalysis.ThrottleLimit := 1;
    lAnalysis.CacheTtlSeconds := 3600;
    lResult := lScanner.AnalyzeRepositories(lAnalysis, lQueue, nil, 47);
    Assert.IsTrue(lResult.Succeeded, lResult.Error);
    Assert.IsTrue(lReloaded.LoadFromFile(lPath, lError), lError);
    Assert.AreEqual(2, Length(lReloaded.GetInventory));
    Assert.AreEqual(lRepo, lReloaded.GetInventory[0]);
    Assert.AreEqual(lMissing, lReloaded.GetInventory[1]);
    Assert.IsFalse(lReloaded.TryGetStatus(lNewRepo, lStatus));
    Assert.IsTrue(lReloaded.TryGetStatus(lRepo, lStatus));
    Assert.AreEqual('main', lStatus.Branch);
    Assert.IsNotEmpty(lStatus.LastAnalyzedUtc);
  finally
    g.Clear;
    lCancel := nil;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TGitParsingTests.ParseStatusPorcelain_StagedAndUnstaged;
var
  lLines: TArray<string>;
  lParse: TGitStatusParse;
begin
  lLines := ['M  src/Unit1.pas', ' M src/Unit2.pas', '?? new.txt'];
  lParse := TGitClient.ParseStatusPorcelain(lLines);

  Assert.IsTrue(lParse.HasStaged, 'Expected staged changes');
  Assert.IsTrue(lParse.HasUnstaged, 'Expected unstaged changes');
  Assert.IsTrue(lParse.HasUntracked, 'Expected untracked changes');
  Assert.IsTrue(lParse.Summary.Contains('Unit1.pas'), 'Expected Unit1.pas in summary');
  Assert.IsTrue(lParse.Summary.Contains('Unit2.pas'), 'Expected Unit2.pas in summary');
  Assert.IsTrue(lParse.Summary.Contains('new.txt'), 'Expected new.txt in summary');
end;

procedure TGitParsingTests.ParseAheadBehind_Basic;
var
  lAhead: Integer;
  lBehind: Integer;
  lOk: Boolean;
begin
  lOk := TGitClient.ParseAheadBehind('3 5', lAhead, lBehind);
  Assert.IsTrue(lOk);
  Assert.AreEqual(3, lAhead);
  Assert.AreEqual(5, lBehind);

  lOk := TGitClient.ParseAheadBehind('10'#9'2', lAhead, lBehind);
  Assert.IsTrue(lOk);
  Assert.AreEqual(10, lAhead);
  Assert.AreEqual(2, lBehind);
end;

procedure TGitParsingTests.IsPullConflictError_DetectsFastForwardAbort;
begin
  Assert.IsTrue(TGitClient.IsPullConflictError('fatal: Not possible to fast-forward, aborting.'));
  Assert.IsTrue(TGitClient.IsPullConflictError('CONFLICT (content): Merge conflict in src/main.pas'));
end;

procedure TGitParsingTests.IsPullConflictError_IgnoresNetworkFailures;
begin
  Assert.IsFalse(TGitClient.IsPullConflictError('fatal: unable to access https://example.com/: Could not resolve host: example.com'));
  Assert.IsFalse(TGitClient.IsPullConflictError('fatal: Authentication failed for https://example.com/'));
end;

procedure TGitParsingTests.LocalFirstStatus_QueuesBeforeAndAfterStaleFetch;
var
  g: TGarbos;
  lCache: TRepoCache;
  lEvent: TUiEvent;
  lFinalStatus: TRepoStatus;
  lGit: TGitClient;
  lLocalRoot: string;
  lPath: string;
  lPublisherRoot: string;
  lQueue: TUiEventQueue;
  lRemoteRoot: string;
  lScanner: TTestRepoScanner;
  lTempRoot: string;
begin
  lTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseLocalFirst-' + TPath.GetRandomFileName);
  ForceDirectories(lTempRoot);
  try
    GC(lGit, TGitClient.Create, g);
    GC(lScanner, TTestRepoScanner.Create(lGit), g);
    GC(lCache, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);

    lRemoteRoot := TPath.Combine(lTempRoot, 'remote.git');
    lLocalRoot := TPath.Combine(lTempRoot, 'local');
    lPublisherRoot := TPath.Combine(lTempRoot, 'publisher');
    RunGit(lGit, lTempRoot, ['init', '--bare', '--initial-branch=main', lRemoteRoot]);
    RunGit(lGit, lTempRoot, ['init', '--initial-branch=main', lLocalRoot]);
    RunGit(lGit, lLocalRoot, ['config', 'user.email', 'repopulse-tests@example.invalid']);
    RunGit(lGit, lLocalRoot, ['config', 'user.name', 'RepoPulse Tests']);
    lPath := TPath.Combine(lLocalRoot, 'state.txt');
    TFile.WriteAllText(lPath, 'one'#13#10);
    RunGit(lGit, lLocalRoot, ['add', 'state.txt']);
    RunGit(lGit, lLocalRoot, ['commit', '-m', 'one']);
    RunGit(lGit, lLocalRoot, ['remote', 'add', 'origin', lRemoteRoot]);
    RunGit(lGit, lLocalRoot, ['push', '-u', 'origin', 'main']);

    RunGit(lGit, lTempRoot, ['clone', lRemoteRoot, lPublisherRoot]);
    RunGit(lGit, lPublisherRoot, ['config', 'user.email', 'repopulse-tests@example.invalid']);
    RunGit(lGit, lPublisherRoot, ['config', 'user.name', 'RepoPulse Tests']);
    lPath := TPath.Combine(lPublisherRoot, 'state.txt');
    TFile.WriteAllText(lPath, 'one'#13#10'two'#13#10);
    RunGit(lGit, lPublisherRoot, ['add', 'state.txt']);
    RunGit(lGit, lPublisherRoot, ['commit', '-m', 'two']);
    RunGit(lGit, lPublisherRoot, ['push', 'origin', 'main']);

    Assert.IsTrue(lScanner.CheckLocalFirst(lLocalRoot, lCache, lQueue, 81, lFinalStatus));
    Assert.AreEqual(2, lQueue.Count);
    Assert.IsTrue(lQueue.TryDequeue(lEvent));
    Assert.AreEqual(TUiEventKind.uekRepoResult, lEvent.Kind);
    Assert.AreEqual(Int64(81), lEvent.Generation);
    Assert.AreEqual(0, lEvent.RepoStatus.Behind,
      'The first event must use local refs without waiting for fetch');
    Assert.IsTrue(lQueue.TryDequeue(lEvent));
    Assert.AreEqual(1, lEvent.RepoStatus.Behind,
      'The second event must update the same row after fetch');
    Assert.AreEqual(lLocalRoot, lEvent.RepoStatus.RepoRoot);
    Assert.AreEqual(1, lFinalStatus.Behind);
    Assert.IsTrue(lCache.TryGetStatus(lLocalRoot, lFinalStatus), 'Local-first analysis must retain its completed result');
    Assert.AreEqual(1, lFinalStatus.Behind);
    Assert.IsTrue(lFinalStatus.LastAnalyzedUtc <> '');
  finally
    g.Clear;
    if DirectoryExists(lTempRoot) then
      TDirectory.Delete(lTempRoot, True);
  end;
end;

procedure TGitParsingTests.LocalFirstStatus_FreshCacheQueuesOnceWithoutFetch;
var
  g: TGarbos;
  lCache: TRepoCache;
  lFinalStatus: TRepoStatus;
  lGit: TGitClient;
  lLocalRoot: string;
  lPath: string;
  lQueue: TUiEventQueue;
  lRemoteRoot: string;
  lScanner: TTestRepoScanner;
  lTempRoot: string;
  lUpdate: TRepoCacheUpdate;
begin
  lTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseCacheHit-' + TPath.GetRandomFileName);
  ForceDirectories(lTempRoot);
  try
    GC(lGit, TGitClient.Create, g);
    GC(lScanner, TTestRepoScanner.Create(lGit), g);
    GC(lCache, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);

    lRemoteRoot := TPath.Combine(lTempRoot, 'remote.git');
    lLocalRoot := TPath.Combine(lTempRoot, 'local');
    RunGit(lGit, lTempRoot, ['init', '--bare', '--initial-branch=main', lRemoteRoot]);
    RunGit(lGit, lTempRoot, ['init', '--initial-branch=main', lLocalRoot]);
    RunGit(lGit, lLocalRoot, ['config', 'user.email', 'repopulse-tests@example.invalid']);
    RunGit(lGit, lLocalRoot, ['config', 'user.name', 'RepoPulse Tests']);
    lPath := TPath.Combine(lLocalRoot, 'state.txt');
    TFile.WriteAllText(lPath, 'one'#13#10);
    RunGit(lGit, lLocalRoot, ['add', 'state.txt']);
    RunGit(lGit, lLocalRoot, ['commit', '-m', 'one']);
    RunGit(lGit, lLocalRoot, ['remote', 'add', 'origin', lRemoteRoot]);
    RunGit(lGit, lLocalRoot, ['push', '-u', 'origin', 'main']);

    lUpdate := Default(TRepoCacheUpdate);
    lUpdate.Key := lLocalRoot.ToLowerInvariant;
    lUpdate.LastFetchUtc := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
    lUpdate.LastFetchOk := True;
    lUpdate.HasLastFetchOk := True;
    lCache.ApplyUpdate(lUpdate);

    Assert.IsTrue(lScanner.CheckLocalFirst(lLocalRoot, lCache, lQueue, 82, lFinalStatus));
    Assert.AreEqual(1, lQueue.Count);
    Assert.AreEqual('', lFinalStatus.CacheUpdate.Key,
      'A fresh cache entry must skip the remote fetch');
    Assert.IsTrue(lCache.TryGetStatus(lLocalRoot, lFinalStatus), 'Local-only result must be committed before returning');
    Assert.IsTrue(lFinalStatus.LastAnalyzedUtc <> '');
  finally
    g.Clear;
    if DirectoryExists(lTempRoot) then
      TDirectory.Delete(lTempRoot, True);
  end;
end;

procedure TGitParsingTests.LocalFirstStatus_CorruptIndexPublishesFailureAndRecovers;
var
  g: TGarbos;
  lCache: TRepoCache;
  lEvent: TUiEvent;
  lGit: TGitClient;
  lIndexBytes: TBytes;
  lIndexPath: string;
  lQueue: TUiEventQueue;
  lRepoRoot: string;
  lScanner: TTestRepoScanner;
  lStatus: TRepoStatus;
  lTempRoot: string;
begin
  lTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseScanFailure-' +
    TPath.GetRandomFileName);
  lRepoRoot := TPath.Combine(lTempRoot, 'repo');
  ForceDirectories(lTempRoot);
  try
    GC(lGit, TGitClient.Create, g);
    GC(lScanner, TTestRepoScanner.Create(lGit), g);
    GC(lCache, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);
    RunGit(lGit, lTempRoot, ['init', '--initial-branch=main', lRepoRoot]);
    RunGit(lGit, lRepoRoot, ['config', 'user.email', 'repopulse-tests@example.invalid']);
    RunGit(lGit, lRepoRoot, ['config', 'user.name', 'RepoPulse Tests']);
    TFile.WriteAllText(TPath.Combine(lRepoRoot, 'tracked.txt'), 'tracked'#13#10);
    RunGit(lGit, lRepoRoot, ['add', 'tracked.txt']);
    RunGit(lGit, lRepoRoot, ['commit', '-m', 'initial']);

    lIndexPath := TPath.Combine(lRepoRoot, '.git\index');
    lIndexBytes := TFile.ReadAllBytes(lIndexPath);
    try
      TFile.WriteAllBytes(lIndexPath, TBytes.Create(1, 2, 3));

      Assert.IsTrue(lScanner.CheckLocalFirst(lRepoRoot, lCache, lQueue, 91, lStatus));
      Assert.IsTrue(lStatus.ScanFailed);
      Assert.IsTrue(Trim(lStatus.ScanError) <> '');
      Assert.IsTrue(lStatus.HasProblem);
      Assert.IsTrue(lQueue.TryDequeue(lEvent));
      Assert.AreEqual(TUiEventKind.uekRepoResult, lEvent.Kind);
      Assert.AreEqual(Int64(91), lEvent.Generation);
      Assert.IsTrue(lEvent.RepoStatus.ScanFailed);
      Assert.IsTrue(lCache.TryGetStatus(lRepoRoot, lStatus), 'Failed attempt must reach shared cache');
      Assert.IsTrue(lStatus.ScanFailed);
    finally
      TFile.WriteAllBytes(lIndexPath, lIndexBytes);
    end;

    Assert.IsTrue(lScanner.CheckLocalFirst(lRepoRoot, lCache, lQueue, 92, lStatus));
    Assert.IsFalse(lStatus.ScanFailed);
    Assert.AreEqual('', lStatus.ScanError);
    Assert.IsTrue(lQueue.TryDequeue(lEvent));
    Assert.AreEqual(Int64(92), lEvent.Generation);
    Assert.IsFalse(lEvent.RepoStatus.ScanFailed);
  finally
    g.Clear;
    if DirectoryExists(lTempRoot) then
      TDirectory.Delete(lTempRoot, True);
  end;
end;

procedure TGitParsingTests.RefreshStatus_RegularRepoAheadOfOriginNeedsMainFastForward;
var
  g: TGarbos;
  lGit: TGitClient;
  lScanner: TTestRepoScanner;
  lCache: TRepoCache;
  lTempRoot: string;
  lRemoteRoot: string;
  lRepoRoot: string;
  lFilePath: string;
  lStatus: TRepoStatus;
  lError: string;
begin
  lTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseTests-' + TPath.GetRandomFileName);
  ForceDirectories(lTempRoot);
  try
    GC(lGit, TGitClient.Create, g);
    GC(lScanner, TTestRepoScanner.Create(lGit), g);
    GC(lCache, TRepoCache.Create, g);

    lRemoteRoot := TPath.Combine(lTempRoot, 'remote.git');
    lRepoRoot := TPath.Combine(lTempRoot, 'repo');
    RunGit(lGit, lTempRoot, ['init', '--bare', '--initial-branch=main', lRemoteRoot]);
    RunGit(lGit, lTempRoot, ['init', '--initial-branch=main', lRepoRoot]);
    RunGit(lGit, lRepoRoot, ['config', 'user.email', 'repopulse-tests@example.invalid']);
    RunGit(lGit, lRepoRoot, ['config', 'user.name', 'RepoPulse Tests']);

    lFilePath := TPath.Combine(lRepoRoot, 'state.txt');
    TFile.WriteAllText(lFilePath, 'remote'#13#10);
    RunGit(lGit, lRepoRoot, ['add', 'state.txt']);
    RunGit(lGit, lRepoRoot, ['commit', '-m', 'remote']);
    RunGit(lGit, lRepoRoot, ['remote', 'add', 'origin', lRemoteRoot]);
    RunGit(lGit, lRepoRoot, ['push', '-u', 'origin', 'main']);

    Assert.IsTrue(lScanner.BuildStatus(lRepoRoot, lCache, lStatus), lError);
    Assert.IsFalse(lStatus.SubmoduleNeedsMainFastForward,
      'A regular branch aligned with origin/main must not expose no-fast-forward attention state');

    TFile.WriteAllText(lFilePath, 'remote'#13#10'local'#13#10);
    RunGit(lGit, lRepoRoot, ['add', 'state.txt']);
    RunGit(lGit, lRepoRoot, ['commit', '-m', 'local']);

    Assert.IsTrue(lScanner.BuildStatus(lRepoRoot, lCache, lStatus), lError);
    Assert.IsFalse(lStatus.IsSubmodule, 'Fixture must be a regular repository');
    Assert.IsTrue(lStatus.SubmoduleNeedsMainFastForward,
      'A regular branch ahead of origin/main must expose no-fast-forward attention state');
    Assert.AreEqual('origin/main', lStatus.SubmoduleMainRemoteRef);
  finally
    g.Clear;
    if DirectoryExists(lTempRoot) then
      TDirectory.Delete(lTempRoot, True);
  end;
end;

procedure TGitParsingTests.RefreshStatus_UnrelatedHistorySuppressesDirectionalState;
var
  g: TGarbos;
  lCache: TRepoCache;
  lFilePath: string;
  lGit: TGitClient;
  lRemoteRoot: string;
  lRemoteWorkRoot: string;
  lRepoRoot: string;
  lScanner: TTestRepoScanner;
  lStatus: TRepoStatus;
  lTempRoot: string;
begin
  lTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseUnrelated-' +
    TPath.GetRandomFileName);
  ForceDirectories(lTempRoot);
  try
    GC(lGit, TGitClient.Create, g);
    GC(lScanner, TTestRepoScanner.Create(lGit), g);
    GC(lCache, TRepoCache.Create, g);

    lRemoteRoot := TPath.Combine(lTempRoot, 'remote.git');
    lRemoteWorkRoot := TPath.Combine(lTempRoot, 'remote-work');
    lRepoRoot := TPath.Combine(lTempRoot, 'repo');
    RunGit(lGit, lTempRoot, ['init', '--bare', '--initial-branch=main', lRemoteRoot]);
    RunGit(lGit, lTempRoot, ['init', '--initial-branch=main', lRemoteWorkRoot]);
    RunGit(lGit, lRemoteWorkRoot, ['config', 'user.email', 'repopulse-tests@example.invalid']);
    RunGit(lGit, lRemoteWorkRoot, ['config', 'user.name', 'RepoPulse Tests']);
    lFilePath := TPath.Combine(lRemoteWorkRoot, 'remote.txt');
    TFile.WriteAllText(lFilePath, 'remote'#13#10);
    RunGit(lGit, lRemoteWorkRoot, ['add', 'remote.txt']);
    RunGit(lGit, lRemoteWorkRoot, ['commit', '-m', 'remote root']);
    RunGit(lGit, lRemoteWorkRoot, ['remote', 'add', 'origin', lRemoteRoot]);
    RunGit(lGit, lRemoteWorkRoot, ['push', '-u', 'origin', 'main']);

    RunGit(lGit, lTempRoot, ['init', '--initial-branch=main', lRepoRoot]);
    RunGit(lGit, lRepoRoot, ['config', 'user.email', 'repopulse-tests@example.invalid']);
    RunGit(lGit, lRepoRoot, ['config', 'user.name', 'RepoPulse Tests']);
    lFilePath := TPath.Combine(lRepoRoot, 'local.txt');
    TFile.WriteAllText(lFilePath, 'local'#13#10);
    RunGit(lGit, lRepoRoot, ['add', 'local.txt']);
    RunGit(lGit, lRepoRoot, ['commit', '-m', 'local root']);
    RunGit(lGit, lRepoRoot, ['remote', 'add', 'origin', lRemoteRoot]);
    RunGit(lGit, lRepoRoot, ['fetch', 'origin']);
    RunGit(lGit, lRepoRoot, ['branch', '--set-upstream-to=origin/main', 'main']);

    Assert.IsTrue(lScanner.BuildStatus(lRepoRoot, lCache, lStatus));
    Assert.IsTrue(lStatus.UnrelatedHistory,
      'HEAD and origin/main have no common ancestor');
    Assert.AreEqual(0, lStatus.Ahead,
      'Disconnected histories must not report a misleading ahead count');
    Assert.AreEqual(0, lStatus.Behind,
      'Disconnected histories must not report a misleading behind count');
    Assert.IsFalse(lStatus.IsOutOfDate,
      'Disconnected histories are not safe Pull candidates');
    Assert.IsFalse(lStatus.HasUnpushed,
      'Disconnected histories need recovery, not a normal Push classification');
    Assert.IsFalse(lStatus.SubmoduleNeedsMainFastForward,
      'The unrelated-history warning replaces the no-fast-forward warning');
    Assert.IsTrue(lStatus.HasProblem);
  finally
    g.Clear;
    if DirectoryExists(lTempRoot) then
      TDirectory.Delete(lTempRoot, True);
  end;
end;

procedure TGitParsingTests.Pull_DetachedSubmoduleFastForwardsRemoteDefaultAndRemainsDetached;
var
  g: TGarbos;
  lAhead: Integer;
  lBehind: Integer;
  lBranch: string;
  lChildSourceRoot: string;
  lError: string;
  lGit: TGitClient;
  lParentRoot: string;
  lRemoteRoot: string;
  lResultAfter: TGitResult;
  lResultBefore: TGitResult;
  lSubmoduleRoot: string;
  lTempRoot: string;
begin
  lTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseDetachedPull-' +
    TPath.GetRandomFileName);
  ForceDirectories(lTempRoot);
  try
    GC(lGit, TGitClient.Create, g);
    lRemoteRoot := TPath.Combine(lTempRoot, 'remote.git');
    lChildSourceRoot := TPath.Combine(lTempRoot, 'child-source');
    lParentRoot := TPath.Combine(lTempRoot, 'parent');
    RunGit(lGit, lTempRoot, ['init', '--bare', '--initial-branch=main', lRemoteRoot]);
    RunGit(lGit, lTempRoot, ['init', '--initial-branch=main', lChildSourceRoot]);
    RunGit(lGit, lChildSourceRoot, ['config', 'user.email', 'repopulse-tests@example.invalid']);
    RunGit(lGit, lChildSourceRoot, ['config', 'user.name', 'RepoPulse Tests']);
    RunGit(lGit, lChildSourceRoot, ['commit', '--allow-empty', '-m', 'initial']);
    RunGit(lGit, lChildSourceRoot, ['remote', 'add', 'origin', lRemoteRoot]);
    RunGit(lGit, lChildSourceRoot, ['push', '-u', 'origin', 'main']);

    RunGit(lGit, lTempRoot, ['init', '--initial-branch=main', lParentRoot]);
    RunGit(lGit, lParentRoot, ['config', 'user.email', 'repopulse-tests@example.invalid']);
    RunGit(lGit, lParentRoot, ['config', 'user.name', 'RepoPulse Tests']);
    RunGit(lGit, lParentRoot,
      ['-c', 'protocol.file.allow=always', 'submodule', 'add', lRemoteRoot, 'modules/child']);
    RunGit(lGit, lParentRoot, ['commit', '-m', 'add submodule']);
    lSubmoduleRoot := TPath.Combine(lParentRoot, 'modules\child');
    RunGit(lGit, lSubmoduleRoot, ['checkout', '--detach', 'HEAD']);

    RunGit(lGit, lChildSourceRoot, ['commit', '--allow-empty', '-m', 'remote update']);
    RunGit(lGit, lChildSourceRoot, ['push', 'origin', 'main']);
    RunGit(lGit, lSubmoduleRoot, ['fetch', 'origin']);
    Assert.IsTrue(lGit.TryGetAheadBehind(lSubmoduleRoot, 'origin/main', lAhead,
      lBehind, lError), lError);
    Assert.AreEqual(0, lAhead);
    Assert.AreEqual(1, lBehind);

    Assert.IsTrue(lGit.TryPull(lSubmoduleRoot, lError), lError);
    Assert.IsTrue(lGit.TryGetBranch(lSubmoduleRoot, lBranch, lError), lError);
    Assert.AreEqual(rsBranchDetached, lBranch);
    Assert.IsTrue(lGit.TryGetAheadBehind(lSubmoduleRoot, 'origin/main', lAhead,
      lBehind, lError), lError);
    Assert.AreEqual(0, lAhead);
    Assert.AreEqual(0, lBehind);

    RunGit(lGit, lSubmoduleRoot, ['config', 'user.email', 'repopulse-tests@example.invalid']);
    RunGit(lGit, lSubmoduleRoot, ['config', 'user.name', 'RepoPulse Tests']);
    RunGit(lGit, lSubmoduleRoot, ['commit', '--allow-empty', '-m', 'detached local update']);
    RunGit(lGit, lChildSourceRoot, ['commit', '--allow-empty', '-m', 'second remote update']);
    RunGit(lGit, lChildSourceRoot, ['push', 'origin', 'main']);
    Assert.IsTrue(lGit.TryRunGit(lSubmoduleRoot, ['rev-parse', 'HEAD'],
      lResultBefore, lError, 0), lError);

    Assert.IsFalse(lGit.TryPull(lSubmoduleRoot, lError));
    Assert.Contains(lError.ToLowerInvariant, 'fast-forward');
    Assert.IsTrue(lGit.TryRunGit(lSubmoduleRoot, ['rev-parse', 'HEAD'],
      lResultAfter, lError, 0), lError);
    Assert.AreEqual(lResultBefore.OutputText.Trim, lResultAfter.OutputText.Trim,
      'A divergent detached Pull must not move HEAD');
  finally
    g.Clear;
    if DirectoryExists(lTempRoot) then
      TDirectory.Delete(lTempRoot, True);
  end;
end;

procedure TGitParsingTests.ResolveSuperprojectRoot_RealSubmodule;
var
  g: TGarbos;
  lGit: TGitClient;
  lScanner: TTestRepoScanner;
  lCache: TRepoCache;
  lTempRoot: string;
  lChildSourceRoot: string;
  lParentRoot: string;
  lSubmoduleRoot: string;
  lResolvedRoot: string;
  lStatus: TRepoStatus;
  lError: string;
begin
  lTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseTests-' + TPath.GetRandomFileName);
  ForceDirectories(lTempRoot);
  try
    GC(lGit, TGitClient.Create, g);

    lChildSourceRoot := TPath.Combine(lTempRoot, 'child-source');
    RunGit(lGit, lTempRoot, ['init', '--initial-branch=main', lChildSourceRoot]);
    RunGit(lGit, lChildSourceRoot, ['config', 'user.email', 'repopulse-tests@example.invalid']);
    RunGit(lGit, lChildSourceRoot, ['config', 'user.name', 'RepoPulse Tests']);
    TFile.WriteAllText(TPath.Combine(lChildSourceRoot, 'child.txt'), 'child'#13#10);
    RunGit(lGit, lChildSourceRoot, ['add', 'child.txt']);
    RunGit(lGit, lChildSourceRoot, ['commit', '-m', 'child']);

    lParentRoot := TPath.Combine(lTempRoot, 'parent');
    RunGit(lGit, lTempRoot, ['init', '--initial-branch=main', lParentRoot]);
    RunGit(lGit, lParentRoot, ['config', 'user.email', 'repopulse-tests@example.invalid']);
    RunGit(lGit, lParentRoot, ['config', 'user.name', 'RepoPulse Tests']);
    RunGit(lGit, lParentRoot,
      ['-c', 'protocol.file.allow=always', 'submodule', 'add', lChildSourceRoot, 'modules/child']);
    RunGit(lGit, lParentRoot, ['commit', '-m', 'add submodule']);

    lSubmoduleRoot := TPath.Combine(lParentRoot, 'modules\child');
    Assert.IsTrue(lGit.TryGetSuperprojectRoot(lSubmoduleRoot, lResolvedRoot, lError), lError);
    Assert.IsTrue(SameText(ExcludeTrailingPathDelimiter(lParentRoot),
      ExcludeTrailingPathDelimiter(lResolvedRoot)), Format('Expected [%s] but got [%s]',
      [lParentRoot, lResolvedRoot]));

    GC(lScanner, TTestRepoScanner.Create(lGit), g);
    GC(lCache, TRepoCache.Create, g);
    Assert.IsTrue(lScanner.BuildStatus(lSubmoduleRoot, lCache, lStatus));
    Assert.IsTrue(lStatus.IsSubmodule, 'The scanner must identify the real submodule');
    Assert.IsTrue(SameText(lParentRoot, lStatus.SuperprojectRoot),
      'The scanned status must retain its normalized superproject root');

    Assert.IsTrue(lGit.TryGetSuperprojectRoot(lParentRoot, lResolvedRoot, lError), lError);
    Assert.AreEqual('', lResolvedRoot, 'A regular repository has no superproject root');
  finally
    g.Clear;
    if DirectoryExists(lTempRoot) then
      TDirectory.Delete(lTempRoot, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TGitParsingTests);

end.
