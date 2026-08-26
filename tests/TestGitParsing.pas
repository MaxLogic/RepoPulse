unit TestGitParsing;

interface

uses
  System.DateUtils, System.IOUtils, System.SysUtils,

  AutoFree, DUnitX.TestFramework,
  UGitClient, UModels, URepoCache, URepoScanner, UUiEventQueue;

type
  [TestFixture]
  TGitParsingTests = class
  private
    procedure RunGit(const aGit: TGitClient; const aRepo: string; const aArgs: TArray<string>);
  public
    [Test]
    procedure ParseStatusPorcelain_StagedAndUnstaged;
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
    procedure RefreshStatus_RegularRepoAheadOfOriginNeedsMainFastForward;
    [Test]
    procedure ResolveSuperprojectRoot_RealSubmodule;
  end;

implementation

type
  TTestRepoScanner = class(TRepoScanner)
  public
    function BuildStatus(const aRepoRoot: string; const aCache: TRepoCache; out aStatus: TRepoStatus): Boolean;
    function CheckLocalFirst(const aRepoRoot: string; const aCache: TRepoCache;
      const aQueue: TUiEventQueue; const aGeneration: Int64; out aStatus: TRepoStatus): Boolean;
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
  Result := CheckRepoStatusLocalFirst(aRepoRoot, [aRepoRoot], aCache, 3600, aQueue, aStatus);
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
