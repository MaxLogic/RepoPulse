unit TestRepoDiscovery;

interface

uses
  System.IOUtils, System.StrUtils, System.SysUtils,

  AutoFree, DUnitX.TestFramework,
  UGitClient, UPathRules, URepoCache, URepoScanner, UUiEventQueue;

type
  TTestRepoScanner = class(TRepoScanner)
  public
    function FindCandidatesForTest(const aRoots: TArray<string>; const aFilterPattern: string;
      const aDepthLimit: Integer; const aIgnorePatterns: TArray<TIgnorePattern>;
      out aSkippedDueToCap: Boolean; const aQueue: TUiEventQueue = nil;
      const aGeneration: Int64 = 0): TArray<string>;
    function NewEventForTest(const aKind: TUiEventKind; const aGeneration: Int64): TUiEvent;
    function PublishCachedForTest(const aCache: TRepoCache; const aFingerprint: string;
      const aQueue: TUiEventQueue; const aGeneration: Int64): Integer;
  end;

  [TestFixture]
  TRepoDiscoveryTests = class
  private
    procedure CreateGitMarker(const aRepoRoot: string);
  public
    [Test]
    procedure FindCandidates_ScansAllRootsFiltersExcludesAndDeduplicates;
    [Test]
    procedure FindCandidates_QueuesWaitingRowsAsRepositoriesAreFound;
    [Test]
    procedure NewUiEvent_UsesScanGeneration;
    [Test]
    procedure PublishCachedInventory_QueuesValidatedWaitingRows;
  end;

implementation

function TTestRepoScanner.FindCandidatesForTest(const aRoots: TArray<string>;
  const aFilterPattern: string; const aDepthLimit: Integer;
  const aIgnorePatterns: TArray<TIgnorePattern>; out aSkippedDueToCap: Boolean;
  const aQueue: TUiEventQueue; const aGeneration: Int64): TArray<string>;
begin
  fGeneration := aGeneration;
  Result := FindRepoCandidates(aRoots, aFilterPattern, aDepthLimit, aIgnorePatterns,
    aSkippedDueToCap, aQueue);
end;

procedure TRepoDiscoveryTests.CreateGitMarker(const aRepoRoot: string);
begin
  ForceDirectories(TPath.Combine(aRepoRoot, '.git'));
end;

procedure TRepoDiscoveryTests.FindCandidates_QueuesWaitingRowsAsRepositoriesAreFound;
var
  lEvent: TUiEvent;
  lGit: TGitClient;
  lQueue: TUiEventQueue;
  lRepoOne: string;
  lRepoTwo: string;
  lRoot: string;
  lScanner: TTestRepoScanner;
  lSkipped: Boolean;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseWaiting-' + TPath.GetRandomFileName);
  lRepoOne := TPath.Combine(lRoot, 'RepoOne');
  lRepoTwo := TPath.Combine(lRoot, 'Team\RepoTwo');
  CreateGitMarker(lRepoOne);
  CreateGitMarker(lRepoTwo);
  lGit := TGitClient.Create;
  lScanner := TTestRepoScanner.Create(lGit);
  lQueue := TUiEventQueue.Create;
  try
    Assert.AreEqual(2, Length(lScanner.FindCandidatesForTest([lRoot], '*', 3, [], lSkipped,
      lQueue, 73)));
    Assert.AreEqual(2, lQueue.Count);
    Assert.IsTrue(lQueue.TryDequeue(lEvent));
    Assert.AreEqual(TUiEventKind.uekRepoWaiting, lEvent.Kind);
    Assert.AreEqual(Int64(73), lEvent.Generation);
    Assert.IsTrue(MatchText(lEvent.RepoRoot, [lRepoOne, lRepoTwo]));
    Assert.IsTrue(lQueue.TryDequeue(lEvent));
    Assert.AreEqual(TUiEventKind.uekRepoWaiting, lEvent.Kind);
    Assert.AreEqual(Int64(73), lEvent.Generation);
    Assert.IsTrue(MatchText(lEvent.RepoRoot, [lRepoOne, lRepoTwo]));
  finally
    lQueue.Free;
    lScanner.Free;
    lGit.Free;
    if DirectoryExists(lRoot) then
      TDirectory.Delete(lRoot, True);
  end;
end;

procedure TRepoDiscoveryTests.FindCandidates_ScansAllRootsFiltersExcludesAndDeduplicates;
var
  g: TGarbos;
  lGit: TGitClient;
  lScanner: TTestRepoScanner;
  lTempRoot: string;
  lRootOne: string;
  lRootTwo: string;
  lNestedRoot: string;
  lAlphaRepo: string;
  lBetaRepo: string;
  lIgnoredRepo: string;
  lIgnoreRule: TIgnorePattern;
  lCandidates: TArray<string>;
  lSkipped: Boolean;
begin
  lTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseDiscovery-' + TPath.GetRandomFileName);
  ForceDirectories(lTempRoot);
  try
    lRootOne := TPath.Combine(lTempRoot, 'RootOne');
    lRootTwo := TPath.Combine(lTempRoot, 'RootTwo');
    lNestedRoot := TPath.Combine(lRootOne, 'Team');
    lAlphaRepo := TPath.Combine(lNestedRoot, 'AlphaRepo');
    lBetaRepo := TPath.Combine(lRootTwo, 'Tools\BetaRepo');
    lIgnoredRepo := TPath.Combine(lRootTwo, 'IgnoredRepo');
    CreateGitMarker(lAlphaRepo);
    CreateGitMarker(lBetaRepo);
    CreateGitMarker(lIgnoredRepo);

    lIgnoreRule := Default(TIgnorePattern);
    lIgnoreRule.Pattern := NormalizePathForMatch(lIgnoredRepo);
    lIgnoreRule.HasSlash := True;
    lIgnoreRule.IsAbsolute := True;

    GC(lGit, TGitClient.Create, g);
    GC(lScanner, TTestRepoScanner.Create(lGit), g);
    lCandidates := lScanner.FindCandidatesForTest([lRootOne, lNestedRoot, lRootTwo], '*Repo', 4,
      [lIgnoreRule], lSkipped);

    Assert.IsFalse(lSkipped);
    Assert.AreEqual(2, Length(lCandidates));
    Assert.IsTrue(MatchText(lAlphaRepo, lCandidates));
    Assert.IsTrue(MatchText(lBetaRepo, lCandidates));
  finally
    g.Clear;
    if DirectoryExists(lTempRoot) then
      TDirectory.Delete(lTempRoot, True);
  end;
end;

function TTestRepoScanner.NewEventForTest(const aKind: TUiEventKind;
  const aGeneration: Int64): TUiEvent;
begin
  fGeneration := aGeneration;
  Result := NewUiEvent(aKind);
end;

function TTestRepoScanner.PublishCachedForTest(const aCache: TRepoCache;
  const aFingerprint: string; const aQueue: TUiEventQueue; const aGeneration: Int64): Integer;
begin
  fGeneration := aGeneration;
  Result := PublishCachedInventory(aCache, aFingerprint, aQueue);
end;

procedure TRepoDiscoveryTests.NewUiEvent_UsesScanGeneration;
var
  lGit: TGitClient;
  lScanner: TTestRepoScanner;
  lEvent: TUiEvent;
begin
  lGit := TGitClient.Create;
  lScanner := TTestRepoScanner.Create(lGit);
  try
    lEvent := lScanner.NewEventForTest(TUiEventKind.uekRepoResult, 42);
    Assert.AreEqual(TUiEventKind.uekRepoResult, lEvent.Kind);
    Assert.AreEqual(Int64(42), lEvent.Generation);
  finally
    lScanner.Free;
    lGit.Free;
  end;
end;

procedure TRepoDiscoveryTests.PublishCachedInventory_QueuesValidatedWaitingRows;
var
  lCache: TRepoCache;
  lEvent: TUiEvent;
  lGit: TGitClient;
  lQueue: TUiEventQueue;
  lRepoRoot: string;
  lRoot: string;
  lScanner: TTestRepoScanner;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseWarm-' + TPath.GetRandomFileName);
  lRepoRoot := TPath.Combine(lRoot, 'RepoOne');
  CreateGitMarker(lRepoRoot);
  lGit := TGitClient.Create;
  lScanner := TTestRepoScanner.Create(lGit);
  lCache := TRepoCache.Create;
  lQueue := TUiEventQueue.Create;
  try
    lCache.SetInventory('matching', [lRepoRoot, TPath.Combine(lRoot, 'Missing')]);
    Assert.AreEqual(1, lScanner.PublishCachedForTest(lCache, 'matching', lQueue, 51));
    Assert.AreEqual(1, lQueue.Count);
    Assert.IsTrue(lQueue.TryDequeue(lEvent));
    Assert.AreEqual(TUiEventKind.uekRepoWaiting, lEvent.Kind);
    Assert.AreEqual(Int64(51), lEvent.Generation);
    Assert.AreEqual(lRepoRoot, lEvent.RepoRoot);
  finally
    lQueue.Free;
    lCache.Free;
    lScanner.Free;
    lGit.Free;
    if DirectoryExists(lRoot) then
      TDirectory.Delete(lRoot, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRepoDiscoveryTests);

end.
