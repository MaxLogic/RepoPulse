unit TestRepoDiscovery;

interface

uses
  System.Classes, System.IOUtils, System.StrUtils, System.SysUtils,

  Winapi.Windows,

  AutoFree, DUnitX.TestFramework,
  UFolderSelection, UGitClient, UModels, UPathRules, URepoCache, URepoScanner, UUiEventQueue;

type
  TTestRepoScanner = class(TRepoScanner)
  protected
    function DiscoveryCandidateLimit: Integer; override;
  public
    CandidateLimit: Integer;
    function NewEventForTest(const aKind: TUiEventKind; const aGeneration: Int64): TUiEvent;
  end;

  [TestFixture]
  TRepoDiscoveryTests = class
  private
    procedure CreateGitMarker(const aRepoRoot: string);
    procedure CreateJunction(const aLinkPath, aTargetPath: string);
    procedure RunFixtureCommand(const aExecutable, aArguments: string);
  public
    [Test]
    procedure Discovery_CommitsMarkersWithoutAnalyzingAndRetainsKnownRoots;
    [Test]
    procedure Discovery_FailedSaveRollsBackMembershipButKeepsPendingObservation;
    [Test]
    procedure Discovery_CheckedRulesGitFileDepthAndIgnoresPreserveSnapshots;
    [Test]
    procedure Discovery_UnavailableRootDiscardsEarlierProvisionalAddition;
    [Test]
    procedure Discovery_CandidateCapDiscardsProvisionalMembership;
    [Test]
    procedure Discovery_ReparseDirectoryDoesNotFollowTarget;
    [Test]
    procedure Discovery_DeniedSubtreeDiscardsProvisionalMembership;
    [Test]
    procedure Discovery_UncheckedDeniedParentDoesNotBlockIndependentInclusion;
    [Test]
    procedure Discovery_ScansAllRootsIgnoresAndDeduplicates;
    [Test]
    procedure NewUiEvent_UsesScanGeneration;
  end;

implementation

function TTestRepoScanner.DiscoveryCandidateLimit: Integer;
begin
  if CandidateLimit > 0 then
    Result := CandidateLimit
  else
    Result := inherited DiscoveryCandidateLimit;
end;

procedure TRepoDiscoveryTests.Discovery_CandidateCapDiscardsProvisionalMembership;
var
  g: TGarbos;
  lCache: TRepoCache;
  lScanner: TTestRepoScanner;
  lQueue: TUiEventQueue;
  lRequest: TRepoDiscoveryRequest;
  lResult: TRepoOperationResult;
  lRoot, lPath, lError, lBefore: string;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseCap-' + TPath.GetRandomFileName);
  lPath := TPath.Combine(lRoot, 'cache.json');
  CreateGitMarker(TPath.Combine(lRoot, 'one'));
  CreateGitMarker(TPath.Combine(lRoot, 'two'));
  CreateGitMarker(TPath.Combine(lRoot, 'three'));
  try
    GC(lCache, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);
    Assert.IsTrue(lCache.EnsureLoaded(lPath, lError), lError);
    lCache.SetInventory('', ['Z:\committed']);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    lBefore := TFile.ReadAllText(lPath);
    GC(lScanner, TTestRepoScanner.Create(nil, lCache, lPath), g);
    // Exercise the same production bound with real folders, without a 10000-folder fixture.
    lScanner.CandidateLimit := 2;
    lRequest := Default(TRepoDiscoveryRequest);
    lRequest.Roots := [lRoot];
    lRequest.MaxDepth := 3;
    lRequest.CacheTtlSeconds := 3600;
    lResult := lScanner.DiscoverRepositories(lRequest, lQueue, nil, 49);
    Assert.IsFalse(lResult.Succeeded);
    Assert.IsTrue(lResult.Summary.SkippedDueToCap);
    Assert.AreEqual(2, lResult.Summary.DiscoveredCount);
    Assert.AreEqual(1, Length(lResult.RepoRoots));
    Assert.AreEqual('Z:\committed', lResult.RepoRoots[0]);
    Assert.AreEqual(lBefore, TFile.ReadAllText(lPath));
  finally
    g.Clear;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TRepoDiscoveryTests.CreateJunction(const aLinkPath, aTargetPath: string);
begin
  Assert.IsFalse(aLinkPath.Contains('%') or aTargetPath.Contains('%'));
  RunFixtureCommand(GetEnvironmentVariable('ComSpec'),
    '/d /v:off /c mklink /J "' + aLinkPath + '" "' + aTargetPath + '"');
end;

procedure TRepoDiscoveryTests.RunFixtureCommand(const aExecutable, aArguments: string);
var
  lCommand: string;
  lStartup: TStartupInfo;
  lProcess: TProcessInformation;
  lWait, lExitCode: Cardinal;
begin
  lCommand := '"' + aExecutable + '" ' + aArguments;
  UniqueString(lCommand);
  lStartup := Default(TStartupInfo);
  lStartup.cb := SizeOf(lStartup);
  lProcess := Default(TProcessInformation);
  Assert.IsTrue(CreateProcess(PChar(aExecutable), PChar(lCommand), nil, nil, False,
    CREATE_NO_WINDOW, nil, nil, lStartup, lProcess));
  try
    lWait := WaitForSingleObject(lProcess.hProcess, 5000);
    if lWait <> WAIT_OBJECT_0 then
    begin
      // Stop this fixture-owned child before releasing its filesystem paths.
      TerminateProcess(lProcess.hProcess, 1);
      WaitForSingleObject(lProcess.hProcess, 5000);
      Assert.Fail('Fixture command did not finish');
    end;
    Assert.IsTrue(GetExitCodeProcess(lProcess.hProcess, lExitCode));
    Assert.AreEqual(Cardinal(0), lExitCode);
  finally
    CloseHandle(lProcess.hThread);
    CloseHandle(lProcess.hProcess);
  end;
end;

procedure TRepoDiscoveryTests.Discovery_DeniedSubtreeDiscardsProvisionalMembership;
var
  g: TGarbos;
  lCache: TRepoCache;
  lScanner: TRepoScanner;
  lQueue: TUiEventQueue;
  lRequest: TRepoDiscoveryRequest;
  lResult: TRepoOperationResult;
  lRoot, lRepo, lDenied, lPath, lError, lBefore, lIdentity, lIcacls: string;
  lAclAttempted: Boolean;
  lFindData: TWin32FindData;
  lFindHandle: THandle;
  lFindError: Cardinal;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseDenied-' + TPath.GetRandomFileName);
  lRepo := TPath.Combine(lRoot, 'new');
  lDenied := TPath.Combine(lRoot, 'denied');
  lPath := TPath.Combine(lRoot, 'cache.json');
  CreateGitMarker(lRepo);
  ForceDirectories(TPath.Combine(lDenied, 'child'));
  lAclAttempted := False;
  lIdentity := GetEnvironmentVariable('USERDOMAIN') + '\' + GetEnvironmentVariable('USERNAME');
  lIcacls := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\icacls.exe');
  try
    Assert.IsTrue(IsSameOrDescendantPath(lDenied, lRoot));
    Assert.IsTrue(IsSameOrDescendantPath(lRoot, TPath.GetTempPath));
    Assert.IsTrue(ExtractFileName(lRoot).StartsWith('RepoPulseDenied-'));
    Assert.IsTrue(FileExists(lIcacls));
    Assert.IsFalse(lIdentity.Contains('"'));
    GC(lCache, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);
    Assert.IsTrue(lCache.EnsureLoaded(lPath, lError), lError);
    lCache.SetInventory('', ['Z:\committed']);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    lBefore := TFile.ReadAllText(lPath);
    lAclAttempted := True;
    RunFixtureCommand(lIcacls, '"' + lDenied + '" /deny "' + lIdentity + ':(RD)"');
    lFindHandle := Winapi.Windows.FindFirstFile(PChar(TPath.Combine(lDenied, '*')), lFindData);
    lFindError := GetLastError;
    if lFindHandle <> INVALID_HANDLE_VALUE then
      Winapi.Windows.FindClose(lFindHandle);
    Assert.IsTrue(lFindHandle = INVALID_HANDLE_VALUE, 'Native directory enumeration must fail');
    Assert.AreEqual(Cardinal(ERROR_ACCESS_DENIED), lFindError,
      'Fixture must prove actual native access denial, not rely on RTL exceptions');
    GC(lScanner, TRepoScanner.Create(nil, lCache, lPath), g);
    lRequest := Default(TRepoDiscoveryRequest);
    lRequest.Roots := [lRepo, lDenied];
    lRequest.MaxDepth := 3;
    lRequest.CacheTtlSeconds := 3600;
    lResult := lScanner.DiscoverRepositories(lRequest, lQueue, nil, 54);
    Assert.IsFalse(lResult.Succeeded);
    Assert.IsNotEmpty(lResult.Error);
    Assert.AreEqual(1, lResult.Summary.DiscoveredCount);
    Assert.AreEqual(1, Length(lResult.RepoRoots));
    Assert.AreEqual('Z:\committed', lResult.RepoRoots[0]);
    Assert.AreEqual(lBefore, TFile.ReadAllText(lPath));
  finally
    g.Clear;
    if lAclAttempted then
      RunFixtureCommand(lIcacls, '"' + lDenied + '" /remove:d "' + lIdentity + '"');
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TRepoDiscoveryTests.Discovery_UncheckedDeniedParentDoesNotBlockIndependentInclusion;
var
  g: TGarbos;
  lCache: TRepoCache;
  lScanner: TRepoScanner;
  lQueue: TUiEventQueue;
  lRequest: TRepoDiscoveryRequest;
  lResult: TRepoOperationResult;
  lRoot, lRepo, lDenied, lPath, lError, lBefore, lIdentity, lIcacls: string;
  lAclAttempted: Boolean;
  lFindData: TWin32FindData;
  lFindHandle: THandle;
  lFindError: Cardinal;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseDenied-' + TPath.GetRandomFileName);
  lRepo := TPath.Combine(lRoot, 'new');
  lDenied := TPath.Combine(lRoot, 'denied');
  lPath := TPath.Combine(lRoot, 'cache.json');
  CreateGitMarker(lRepo);
  CreateGitMarker(TPath.Combine(lDenied, 'child'));
  lAclAttempted := False;
  lIdentity := GetEnvironmentVariable('USERDOMAIN') + '\' + GetEnvironmentVariable('USERNAME');
  lIcacls := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\icacls.exe');
  try
    Assert.IsTrue(IsSameOrDescendantPath(lDenied, lRoot));
    Assert.IsTrue(IsSameOrDescendantPath(lRoot, TPath.GetTempPath));
    Assert.IsTrue(ExtractFileName(lRoot).StartsWith('RepoPulseDenied-'));
    Assert.IsTrue(FileExists(lIcacls));
    Assert.IsFalse(lIdentity.Contains('"'));
    GC(lCache, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);
    Assert.IsTrue(lCache.EnsureLoaded(lPath, lError), lError);
    lCache.SetInventory('', ['Z:\committed']);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    lBefore := TFile.ReadAllText(lPath);
    lAclAttempted := True;
    RunFixtureCommand(lIcacls, '"' + lDenied + '" /deny "' + lIdentity + ':(RD)"');
    lFindHandle := Winapi.Windows.FindFirstFile(PChar(TPath.Combine(lDenied, '*')), lFindData);
    lFindError := GetLastError;
    if lFindHandle <> INVALID_HANDLE_VALUE then
      Winapi.Windows.FindClose(lFindHandle);
    Assert.IsTrue(lFindHandle = INVALID_HANDLE_VALUE, 'Native directory enumeration must fail');
    Assert.AreEqual(Cardinal(ERROR_ACCESS_DENIED), lFindError,
      'Fixture must prove actual native access denial, not rely on RTL exceptions');
    GC(lScanner, TRepoScanner.Create(nil, lCache, lPath), g);
    lRequest := Default(TRepoDiscoveryRequest);
    lRequest.Roots := [lRoot];
    lRequest.Rules := SetFolderSelection(lRoot, True, []);
    lRequest.Rules := SetFolderSelection(lDenied, False, lRequest.Rules);
    lRequest.Rules := SetFolderSelection(TPath.Combine(lDenied, 'child'), True, lRequest.Rules);
    lRequest.UsePathSelection := True;
    lRequest.MaxDepth := 3;
    lRequest.CacheTtlSeconds := 3600;
    lResult := lScanner.DiscoverRepositories(lRequest, lQueue, nil, 54);
    Assert.IsTrue(lResult.Succeeded, lResult.Error);
    Assert.AreEqual('', lResult.Error);
    Assert.AreEqual(2, lResult.Summary.DiscoveredCount);
    Assert.AreEqual(3, Length(lResult.RepoRoots));
    Assert.AreEqual('Z:\committed', lResult.RepoRoots[0]);
    Assert.IsTrue(MatchText(NormalizeSelectionPath(lRepo), lResult.RepoRoots));
    Assert.IsTrue(MatchText(NormalizeSelectionPath(TPath.Combine(lDenied, 'child')), lResult.RepoRoots));
    Assert.IsTrue(lBefore <> TFile.ReadAllText(lPath), 'Successful checked-scope discovery must commit additions');
  finally
    g.Clear;
    if lAclAttempted then
      RunFixtureCommand(lIcacls, '"' + lDenied + '" /remove:d "' + lIdentity + '"');
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TRepoDiscoveryTests.Discovery_ReparseDirectoryDoesNotFollowTarget;
var
  g: TGarbos;
  lCache: TRepoCache;
  lScanner: TRepoScanner;
  lQueue: TUiEventQueue;
  lRequest: TRepoDiscoveryRequest;
  lResult: TRepoOperationResult;
  lRoot, lBrowse, lTarget, lLink, lPath: string;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseJunction-' + TPath.GetRandomFileName);
  lBrowse := TPath.Combine(lRoot, 'browse');
  lTarget := TPath.Combine(lRoot, 'target');
  lLink := TPath.Combine(lBrowse, 'junction');
  lPath := TPath.Combine(lRoot, 'cache.json');
  ForceDirectories(lBrowse);
  CreateGitMarker(lTarget);
  try
    CreateJunction(lLink, lTarget);
    Assert.IsTrue((GetFileAttributes(PChar(lLink)) and FILE_ATTRIBUTE_REPARSE_POINT) <> 0);
    GC(lCache, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);
    GC(lScanner, TRepoScanner.Create(nil, lCache, lPath), g);
    lRequest := Default(TRepoDiscoveryRequest);
    lRequest.Roots := [lBrowse, lLink];
    lRequest.MaxDepth := 20;
    lRequest.CacheTtlSeconds := 3600;
    lResult := lScanner.DiscoverRepositories(lRequest, lQueue, nil, 50);
    Assert.IsTrue(lResult.Succeeded, lResult.Error);
    Assert.AreEqual(0, lResult.Summary.DiscoveredCount);
    Assert.AreEqual(0, Length(lResult.RepoRoots));
  finally
    g.Clear;
    if GetFileAttributes(PChar(lLink)) <> INVALID_FILE_ATTRIBUTES then
      if not Winapi.Windows.RemoveDirectory(PChar(lLink)) then
        Assert.Fail('Cannot remove junction safely; retained fixture at ' + lRoot);
    Assert.IsTrue(DirectoryExists(TPath.Combine(lTarget, '.git')));
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TRepoDiscoveryTests.Discovery_UnavailableRootDiscardsEarlierProvisionalAddition;
var
  g: TGarbos;
  lCache, lReloaded: TRepoCache;
  lScanner: TRepoScanner;
  lQueue: TUiEventQueue;
  lRequest: TRepoDiscoveryRequest;
  lResult: TRepoOperationResult;
  lEvent: TUiEvent;
  lRoot, lRepo, lPath, lError, lBefore: string;
  lProvisional, lTerminal: Integer;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseMissing-' + TPath.GetRandomFileName);
  lRepo := TPath.Combine(lRoot, 'new');
  lPath := TPath.Combine(lRoot, 'cache.json');
  CreateGitMarker(lRepo);
  try
    GC(lCache, TRepoCache.Create, g);
    GC(lReloaded, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);
    Assert.IsTrue(lCache.EnsureLoaded(lPath, lError), lError);
    lCache.SetInventory('', ['Z:\committed']);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    lBefore := TFile.ReadAllText(lPath);
    GC(lScanner, TRepoScanner.Create(nil, lCache, lPath), g);
    lRequest := Default(TRepoDiscoveryRequest);
    lRequest.Roots := [lRepo, TPath.Combine(lRoot, 'missing')];
    lRequest.MaxDepth := 1;
    lRequest.CacheTtlSeconds := 3600;
    lResult := lScanner.DiscoverRepositories(lRequest, lQueue, nil, 48);
    Assert.IsFalse(lResult.Succeeded);
    Assert.IsFalse(lResult.Cancelled);
    Assert.IsNotEmpty(lResult.Error);
    Assert.AreEqual(lBefore, TFile.ReadAllText(lPath));
    Assert.IsTrue(lReloaded.LoadFromFile(lPath, lError), lError);
    Assert.AreEqual(1, Length(lReloaded.GetInventory));
    Assert.AreEqual('Z:\committed', lReloaded.GetInventory[0]);
    lProvisional := 0;
    lTerminal := 0;
    while lQueue.TryDequeue(lEvent) do
    begin
      if lEvent.Kind = TUiEventKind.uekDiscoveryFound then
        Inc(lProvisional);
      if lEvent.Kind = TUiEventKind.uekDiscoveryFinished then
      begin
        Inc(lTerminal);
        Assert.IsFalse(lEvent.OperationSucceeded);
        Assert.AreEqual(1, Length(lEvent.RepoRoots));
      end;
    end;
    Assert.AreEqual(1, lProvisional);
    Assert.AreEqual(1, lTerminal);
  finally
    g.Clear;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TRepoDiscoveryTests.Discovery_CheckedRulesGitFileDepthAndIgnoresPreserveSnapshots;
var
  g: TGarbos;
  lCache, lReloaded: TRepoCache;
  lScanner: TRepoScanner;
  lQueue: TUiEventQueue;
  lRequest: TRepoDiscoveryRequest;
  lResult: TRepoOperationResult;
  lStatus: TRepoStatus;
  lRoot, lExcluded, lIncluded, lSibling, lIgnored, lDeep, lPath, lError: string;
  lRoots: TArray<string>;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseRules-' + TPath.GetRandomFileName);
  lExcluded := TPath.Combine(lRoot, 'team');
  lIncluded := TPath.Combine(lExcluded, 'nested\included');
  lSibling := TPath.Combine(lRoot, 'team-copy');
  lIgnored := TPath.Combine(lRoot, 'ignored');
  lDeep := TPath.Combine(lSibling, 'below-depth');
  lPath := TPath.Combine(lRoot, 'cache.json');
  CreateGitMarker(lExcluded);
  CreateGitMarker(lSibling);
  CreateGitMarker(lIgnored);
  CreateGitMarker(lDeep);
  ForceDirectories(lIncluded);
  TFile.WriteAllText(TPath.Combine(lIncluded, '.git'), 'gitdir: unused-marker-only');
  try
    GC(lCache, TRepoCache.Create, g);
    GC(lReloaded, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);
    Assert.IsTrue(lCache.EnsureLoaded(lPath, lError), lError);
    lCache.SetInventory('', [lDeep, 'Z:\unavailable']);
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := lDeep;
    lStatus.Branch := 'retained';
    lCache.StoreStatus(lStatus, '2026-09-20T01:00:00.000Z');
    GC(lScanner, TRepoScanner.Create(nil, lCache, lPath), g);
    lRequest := Default(TRepoDiscoveryRequest);
    lRequest.Roots := [lRoot];
    lRequest.Rules := SetFolderSelection(lRoot, True, []);
    lRequest.Rules := SetFolderSelection(lExcluded, False, lRequest.Rules);
    lRequest.Rules := SetFolderSelection(lIncluded, True, lRequest.Rules);
    lRequest.UsePathSelection := True;
    lRequest.MaxDepth := 1;
    lRequest.CacheTtlSeconds := 3600;
    SetLength(lRequest.IgnorePatterns, 1);
    lRequest.IgnorePatterns[0].Pattern := 'ignored';
    lResult := lScanner.DiscoverRepositories(lRequest, lQueue, nil, 44);
    Assert.IsTrue(lResult.Succeeded, lResult.Error);
    Assert.AreEqual(2, lResult.Summary.DiscoveredCount);
    lRoots := lResult.RepoRoots;
    Assert.AreEqual(4, Length(lRoots));
    Assert.IsTrue(MatchText(NormalizeSelectionPath(lIncluded), lRoots));
    Assert.IsTrue(MatchText(NormalizeSelectionPath(lSibling), lRoots));
    Assert.IsFalse(MatchText(NormalizeSelectionPath(lExcluded), lRoots));
    Assert.IsFalse(MatchText(NormalizeSelectionPath(lIgnored), lRoots));
    Assert.IsTrue(lReloaded.LoadFromFile(lPath, lError), lError);
    Assert.AreEqual(4, Length(lReloaded.GetInventory));
    Assert.IsTrue(lReloaded.TryGetStatus(lDeep, lStatus));
    Assert.AreEqual('retained', lStatus.Branch);
    Assert.AreEqual('2026-09-20T01:00:00.000Z', lStatus.LastAnalyzedUtc);
  finally
    g.Clear;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TRepoDiscoveryTests.Discovery_FailedSaveRollsBackMembershipButKeepsPendingObservation;
var
  g: TGarbos;
  lCache, lReloaded: TRepoCache;
  lScanner: TRepoScanner;
  lQueue: TUiEventQueue;
  lRequest: TRepoDiscoveryRequest;
  lResult: TRepoOperationResult;
  lStatus: TRepoStatus;
  lLock: TFileStream;
  lRoot, lRepo, lPath, lError: string;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseDiscoverySave-' + TPath.GetRandomFileName);
  lRepo := TPath.Combine(lRoot, 'MarkerOnly');
  lPath := TPath.Combine(lRoot, 'cache.json');
  CreateGitMarker(lRepo);
  try
    GC(lCache, TRepoCache.Create, g);
    GC(lReloaded, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);
    Assert.IsTrue(lCache.EnsureLoaded(lPath, lError), lError);
    lCache.SetInventory('', ['Z:\Committed']);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := 'Z:\Committed';
    lStatus.Branch := 'pending-observation';
    lCache.StoreStatus(lStatus, '2026-09-20T01:00:00.000Z');
    GC(lScanner, TRepoScanner.Create(nil, lCache, lPath), g);
    lRequest := Default(TRepoDiscoveryRequest);
    lRequest.Roots := [lRoot];
    lRequest.MaxDepth := 3;
    lRequest.CacheTtlSeconds := 3600;
    lLock := TFileStream.Create(lPath, fmOpenRead or fmShareDenyWrite);
    try
      lResult := lScanner.DiscoverRepositories(lRequest, lQueue, nil, 43);
      Assert.IsFalse(lResult.Succeeded);
      Assert.IsNotEmpty(lResult.Error, 'A failed commit must explain persistence failure');
      Assert.AreEqual(1, Length(lCache.GetInventory));
      Assert.AreEqual('Z:\Committed', lCache.GetInventory[0]);
      Assert.AreEqual(1, Length(lResult.RepoRoots));
    finally
      lLock.Free;
    end;
    Assert.IsTrue(lCache.FlushPending(lPath, 3600, lError), lError);
    Assert.IsTrue(lReloaded.LoadFromFile(lPath, lError), lError);
    Assert.AreEqual(1, Length(lReloaded.GetInventory), 'A later flush must not leak rejected discovery');
    Assert.IsTrue(lReloaded.TryGetStatus('Z:\Committed', lStatus));
    Assert.AreEqual('pending-observation', lStatus.Branch);
  finally
    g.Clear;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TRepoDiscoveryTests.Discovery_CommitsMarkersWithoutAnalyzingAndRetainsKnownRoots;
var
  g: TGarbos;
  lCache, lReloaded: TRepoCache;
  lScanner: TRepoScanner;
  lQueue: TUiEventQueue;
  lRequest: TRepoDiscoveryRequest;
  lResult: TRepoOperationResult;
  lEvent: TUiEvent;
  lStatus: TRepoStatus;
  lRoot, lRepo, lPath, lError: string;
  lFound, lFinished: Integer;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseDiscovery-' + TPath.GetRandomFileName);
  lRepo := TPath.Combine(lRoot, 'MarkerOnly');
  lPath := TPath.Combine(lRoot, 'cache.json');
  CreateGitMarker(lRepo);
  try
    GC(lCache, TRepoCache.Create, g);
    GC(lReloaded, TRepoCache.Create, g);
    GC(lQueue, TUiEventQueue.Create, g);
    Assert.IsTrue(lCache.EnsureLoaded(lPath, lError), lError);
    lCache.SetInventory('', ['Z:\PreviouslyKnown']);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    // No Git object exists: discovery must use filesystem markers exclusively.
    GC(lScanner, TRepoScanner.Create(nil, lCache, lPath), g);
    lRequest := Default(TRepoDiscoveryRequest);
    lRequest.Roots := [lRoot, lRoot];
    lRequest.MaxDepth := 3;
    lRequest.CacheTtlSeconds := 3600;
    lResult := lScanner.DiscoverRepositories(lRequest, lQueue, nil, 41);
    Assert.IsTrue(lResult.Succeeded, lResult.Error);
    Assert.AreEqual(1, lResult.Summary.DiscoveredCount);
    Assert.AreEqual(2, Length(lResult.RepoRoots));
    Assert.AreEqual('Z:\PreviouslyKnown', lResult.RepoRoots[0]);
    Assert.AreEqual(NormalizeSelectionPath(lRepo), lResult.RepoRoots[1]);
    Assert.IsFalse(lCache.TryGetStatus(lRepo, lStatus), 'Discovery must not invent an observation');
    Assert.IsTrue(lReloaded.LoadFromFile(lPath, lError), lError);
    Assert.AreEqual(2, Length(lReloaded.GetInventory));
    lFound := 0;
    lFinished := 0;
    while lQueue.TryDequeue(lEvent) do
    begin
      Assert.AreEqual(Int64(41), lEvent.Generation);
      if lEvent.Kind = TUiEventKind.uekDiscoveryFound then
        Inc(lFound);
      if lEvent.Kind = TUiEventKind.uekDiscoveryFinished then
      begin
        Inc(lFinished);
        Assert.IsTrue(lEvent.OperationSucceeded);
        Assert.AreEqual(2, Length(lEvent.RepoRoots));
      end;
      Assert.IsFalse(lEvent.Kind = TUiEventKind.uekRepoResult);
    end;
    Assert.AreEqual(1, lFound);
    Assert.AreEqual(1, lFinished);
  finally
    g.Clear;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TRepoDiscoveryTests.CreateGitMarker(const aRepoRoot: string);
begin
  ForceDirectories(TPath.Combine(aRepoRoot, '.git'));
end;

procedure TRepoDiscoveryTests.Discovery_ScansAllRootsIgnoresAndDeduplicates;
var
  g: TGarbos;
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
  lRequest: TRepoDiscoveryRequest;
  lResult: TRepoOperationResult;
  lQueue: TUiEventQueue;
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

    GC(lQueue, TUiEventQueue.Create, g);
    GC(lScanner, TTestRepoScanner.Create(nil, nil, TPath.Combine(lTempRoot, 'cache.json')), g);
    lRequest := Default(TRepoDiscoveryRequest);
    lRequest.Roots := [lRootOne, lNestedRoot, lRootTwo];
    lRequest.MaxDepth := 4;
    lRequest.IgnorePatterns := [lIgnoreRule];
    lRequest.CacheTtlSeconds := 3600;
    lResult := lScanner.DiscoverRepositories(lRequest, lQueue, nil, 53);
    Assert.IsTrue(lResult.Succeeded, lResult.Error);
    Assert.AreEqual(2, lResult.Summary.DiscoveredCount);
    lCandidates := lResult.RepoRoots;

    Assert.IsFalse(lResult.Summary.SkippedDueToCap);
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

initialization
  TDUnitX.RegisterTestFixture(TRepoDiscoveryTests);

end.
