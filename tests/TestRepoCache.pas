unit TestRepoCache;

interface

uses
  System.Classes, System.IOUtils, System.SysUtils, System.Threading,

  AutoFree, DUnitX.TestFramework,
  UModels, URepoCache;

type
  [TestFixture]
  TRepoCacheTests = class
  private
    function CreateRepository(const aParent, aName: string): string;
    procedure AssertRejectedCache(const aJson: string);
  public
    [Test]
    procedure ConcurrentUpdatesAndSaves_PreserveEveryObservation;
    [Test]
    procedure Save_CoalescesUnchangedStateAndRetainsFailedChanges;
    [Test]
    procedure Load_MalformedFetchEntryPreventsOverwrite;
    [Test]
    [TestCase('Object', '0')]
    [TestCase('NumericFolder', '1')]
    procedure Load_MalformedSnapshotFoldersPreventOverwrite(const aCase: Integer);
    [Test]
    procedure EnsureLoaded_PreservesPendingObservations;
    [Test]
    procedure Snapshot_RoundTripsUnavailableRootAndFetchMetadata;
    [Test]
    procedure Snapshot_FailedAnalysisRetainsObservationAndRecovers;
    [Test]
    procedure Save_LockedTargetPreservesBytesCleansTempAndRetries;
    [Test]
    [TestCase('VersionOne', '1')]
    [TestCase('VersionTwo', '2')]
    procedure Load_LegacyFetchMetadataSurvivesMigration(const aVersion: Integer);
    [Test]
    procedure Load_InvalidCachePreventsOverwrite;
    [Test]
    [TestCase('Future', '999')]
    [TestCase('Zero', '0')]
    procedure Load_UnsupportedVersionPreventsOverwrite(const aVersion: Integer);
    [Test]
    procedure Load_EmptyCachePreventsOverwrite;
    [Test]
    [TestCase('MissingVersion', '0')]
    [TestCase('InvalidInventory', '1')]
    [TestCase('InvalidRoot', '2')]
    [TestCase('InvalidRepositories', '3')]
    [TestCase('InvalidSnapshots', '4')]
    procedure Load_MalformedMembersPreventOverwrite(const aCase: Integer);
    [Test]
    procedure BuildScanFingerprint_NormalizesEquivalentSettings;
    [Test]
    procedure BuildScanFingerprint_ChangesWithDiscoverySettings;
    [Test]
    procedure GetValidInventory_RejectsFingerprintMismatchAndStaleRoots;
    [Test]
    procedure Load_VersionOneHasNoInventory;
    [Test]
    procedure Save_WritesVersionThree;
    [Test]
    procedure SaveAndLoad_RoundTripsInventory;
    [Test]
    procedure UnsavedInventory_DoesNotReplaceLastGoodFile;
  end;

implementation

procedure TRepoCacheTests.ConcurrentUpdatesAndSaves_PreserveEveryObservation;
const
  cCount = 128;
var
  g: TGarbos;
  lCache, lLoaded: TRepoCache;
  lPool: TThreadPool;
  lRoots, lErrors: TArray<string>;
  lStatus: TRepoStatus;
  lEntry: TRepoCacheEntry;
  lRoot, lPath, lError: string;
  i: Integer;
begin
  GC(lCache, TRepoCache.Create, g);
  GC(lLoaded, TRepoCache.Create, g);
  GC(lPool, TThreadPool.Create, g);
  lPool.SetMaxWorkerThreads(4);
  lPool.SetMinWorkerThreads(4);
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseConcurrent-' + TPath.GetRandomFileName);
  ForceDirectories(lRoot);
  lPath := TPath.Combine(lRoot, 'cache.json');
  try
    SetLength(lRoots, cCount);
    SetLength(lErrors, cCount);
    for i := 0 to cCount - 1 do
      lRoots[i] := TPath.Combine(lRoot, 'Repo' + IntToStr(i));
    lCache.SetInventory('', lRoots);
    TParallel.For(0, cCount - 1,
      procedure(aIndex: Integer)
      var
        lLocalStatus: TRepoStatus;
        lUpdate: TRepoCacheUpdate;
        lSaveError: string;
      begin
        try
          lLocalStatus := Default(TRepoStatus);
          lLocalStatus.RepoRoot := lRoots[aIndex];
          lLocalStatus.Branch := 'branch-' + IntToStr(aIndex);
          lCache.StoreStatus(lLocalStatus, '2026-09-19T12:00:00.000Z');
          lUpdate := Default(TRepoCacheUpdate);
          lUpdate.Key := lRoots[aIndex];
          lUpdate.OriginUrl := 'origin-' + IntToStr(aIndex);
          lCache.ApplyUpdate(lUpdate);
          if not lCache.SaveToFile(lPath, 3600, lSaveError) then
            lErrors[aIndex] := lSaveError;
        except
          on E: Exception do
            lErrors[aIndex] := E.ClassName + ': ' + E.Message;
        end;
      end, lPool);
    for i := 0 to cCount - 1 do
      Assert.AreEqual('', lErrors[i], 'Concurrent cache operation ' + IntToStr(i));
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    Assert.IsTrue(lLoaded.LoadFromFile(lPath, lError), lError);
    Assert.AreEqual(cCount, Length(lLoaded.GetInventory));
    for i := 0 to cCount - 1 do
    begin
      Assert.IsTrue(lLoaded.TryGetStatus(lRoots[i], lStatus), lRoots[i]);
      Assert.AreEqual('branch-' + IntToStr(i), lStatus.Branch);
      Assert.IsTrue(lLoaded.TryGet(lRoots[i], lEntry), lRoots[i]);
      Assert.AreEqual('origin-' + IntToStr(i), lEntry.OriginUrl);
    end;
    Assert.AreEqual(1, Length(TDirectory.GetFiles(lRoot)));
  finally
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TRepoCacheTests.Save_CoalescesUnchangedStateAndRetainsFailedChanges;
var
  g: TGarbos;
  lCache, lLoaded: TRepoCache;
  lLock: TFileStream;
  lStatus: TRepoStatus;
  lPath, lError: string;
begin
  GC(lCache, TRepoCache.Create, g);
  GC(lLoaded, TRepoCache.Create, g);
  lPath := TPath.GetTempFileName;
  try
    lCache.SetInventory('', ['Z:\Repo']);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    lLock := TFileStream.Create(lPath, fmOpenRead or fmShareDenyWrite);
    try
      Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError),
        'An unchanged snapshot must not rewrite the file: ' + lError);
      Assert.IsFalse(lCache.SaveToFile(lPath, 7200, lError), 'Changed TTL must require publication');
      lStatus := Default(TRepoStatus);
      lStatus.RepoRoot := 'Z:\Repo';
      lStatus.Branch := 'pending';
      lCache.StoreStatus(lStatus, '2026-09-19T12:00:00.000Z');
      Assert.IsFalse(lCache.SaveToFile(lPath, 3600, lError), 'Changed status must require publication');
    finally
      lLock.Free;
    end;
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    Assert.IsTrue(lLoaded.LoadFromFile(lPath, lError), lError);
    Assert.IsTrue(lLoaded.TryGetStatus('Z:\Repo', lStatus));
    Assert.AreEqual('pending', lStatus.Branch);
  finally
    TFile.Delete(lPath);
  end;
end;

procedure TRepoCacheTests.Load_MalformedFetchEntryPreventsOverwrite;
begin
  AssertRejectedCache('{"version":1,"repos":{"Z:\\Repo":"valuable"}}');
end;

procedure TRepoCacheTests.Load_MalformedSnapshotFoldersPreventOverwrite(const aCase: Integer);
const
  cValues: array[0..1] of string = ('{"folder":"valuable"}', '[123]');
begin
  AssertRejectedCache('{"version":3,"inventory":["Z:\\Repo"],"repos":{},' +
    '"snapshots":{"Z:\\Repo":{"matchedFolders":' + cValues[aCase] + '}}}');
end;

procedure TRepoCacheTests.EnsureLoaded_PreservesPendingObservations;
var
  g: TGarbos;
  lCache, lLoaded: TRepoCache;
  lStatus, lRestored: TRepoStatus;
  lPath, lError: string;
begin
  GC(lCache, TRepoCache.Create, g);
  GC(lLoaded, TRepoCache.Create, g);
  lPath := TPath.GetTempFileName;
  try
    lCache.SetInventory('', ['Z:\Offline\Repo']);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    Assert.IsTrue(lLoaded.EnsureLoaded(lPath, lError), lError);
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := 'Z:\Offline\Repo';
    lStatus.Branch := 'pending';
    lLoaded.StoreStatus(lStatus, '2026-09-19T12:00:00.000Z');
    Assert.IsTrue(lLoaded.EnsureLoaded(lPath, lError), lError);
    Assert.IsTrue(lLoaded.TryGetStatus(lStatus.RepoRoot, lRestored),
      'Repeated initialization must not discard pending observations');
    Assert.AreEqual('pending', lRestored.Branch);
    Assert.IsTrue(lLoaded.SaveToFile(lPath, 3600, lError), lError);
    Assert.IsTrue(lCache.LoadFromFile(lPath, lError), lError);
    Assert.IsTrue(lCache.TryGetStatus(lStatus.RepoRoot, lRestored));
    Assert.AreEqual('pending', lRestored.Branch);
  finally
    TFile.Delete(lPath);
  end;
end;

procedure TRepoCacheTests.Load_MalformedMembersPreventOverwrite(const aCase: Integer);
const
  cInvalid: array[0..4] of string = (
    '{}',
    '{"version":2,"inventory":{},"repos":{}}',
    '{"version":2,"inventory":[123],"repos":{}}',
    '{"version":1,"repos":[]}',
    '{"version":3,"inventory":[],"repos":{},"snapshots":[]}'
  );
begin
  AssertRejectedCache(cInvalid[aCase]);
end;

procedure TRepoCacheTests.Load_LegacyFetchMetadataSurvivesMigration(const aVersion: Integer);
var
  g: TGarbos;
  lCache, lLoaded: TRepoCache;
  lEntry: TRepoCacheEntry;
  lStatus: TRepoStatus;
  lPath, lError: string;
  lRoots: TArray<string>;
begin
  GC(lCache, TRepoCache.Create, g);
  GC(lLoaded, TRepoCache.Create, g);
  lPath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(lPath, Format('{"version":%d,"scanFingerprint":"old",' +
      '"inventory":["Z:\\Offline\\Repo"],"repos":{"z:\\offline\\repo":{' +
      '"originUrl":"https://example.invalid/repo.git","lastFetchUtc":"2026-09-18T01:00:00.000Z",' +
      '"lastFetchOk":false,"lastFetchError":"offline"}}}', [aVersion]), TEncoding.UTF8);
    Assert.IsTrue(lCache.LoadFromFile(lPath, lError), lError);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    Assert.IsTrue(lLoaded.LoadFromFile(lPath, lError), lError);
    Assert.IsTrue(lLoaded.TryGet('Z:\Offline\Repo', lEntry));
    Assert.AreEqual('https://example.invalid/repo.git', lEntry.OriginUrl);
    Assert.AreEqual('2026-09-18T01:00:00.000Z', lEntry.LastFetchUtc);
    Assert.IsFalse(lEntry.LastFetchOk);
    Assert.AreEqual('offline', lEntry.LastFetchError);
    Assert.IsFalse(lLoaded.TryGetStatus('Z:\Offline\Repo', lStatus));
    lRoots := lLoaded.GetInventory;
    if aVersion = 2 then
    begin
      Assert.AreEqual(1, Length(lRoots));
      Assert.AreEqual('Z:\Offline\Repo', lRoots[0]);
    end else begin
      Assert.AreEqual(0, Length(lRoots));
    end;
  finally
    TFile.Delete(lPath);
  end;
end;

procedure TRepoCacheTests.Save_LockedTargetPreservesBytesCleansTempAndRetries;
var
  g: TGarbos;
  lCache: TRepoCache;
  lLock: TFileStream;
  lRoot, lPath, lError, lOriginal: string;
begin
  GC(lCache, TRepoCache.Create, g);
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseAtomic-' + TPath.GetRandomFileName);
  ForceDirectories(lRoot);
  lPath := TPath.Combine(lRoot, 'cache.json');
  try
    lCache.SetInventory('', ['Z:\Original']);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    lOriginal := TFile.ReadAllText(lPath, TEncoding.UTF8);
    lCache.SetInventory('', ['Z:\Replacement']);
    lLock := TFileStream.Create(lPath, fmOpenRead or fmShareDenyWrite);
    try
      Assert.IsFalse(lCache.SaveToFile(lPath, 3600, lError), 'Locked replacement must fail');
      Assert.IsNotEmpty(lError);
      Assert.AreEqual(lOriginal, TFile.ReadAllText(lPath, TEncoding.UTF8));
      Assert.AreEqual(1, Length(TDirectory.GetFiles(lRoot)), 'Failed save must remove its temporary file');
    finally
      lLock.Free;
    end;
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    Assert.Contains(TFile.ReadAllText(lPath, TEncoding.UTF8), 'Replacement');
    Assert.AreEqual(1, Length(TDirectory.GetFiles(lRoot)));
  finally
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TRepoCacheTests.Snapshot_FailedAnalysisRetainsObservationAndRecovers;
const
  cRoot = 'Z:\Offline\Repo';
var
  g: TGarbos;
  lCache, lLoaded: TRepoCache;
  lStatus, lRestored: TRepoStatus;
  lPath, lError: string;
begin
  GC(lCache, TRepoCache.Create, g);
  GC(lLoaded, TRepoCache.Create, g);
  lPath := TPath.GetTempFileName;
  try
    lCache.SetInventory('', [cRoot]);
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := cRoot;
    lStatus.Branch := 'main';
    lStatus.Behind := 4;
    lCache.StoreStatus(lStatus, '2026-09-18T01:00:00.000Z');
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := cRoot;
    lStatus.ScanFailed := True;
    lStatus.ScanError := 'root unavailable';
    lCache.StoreStatus(lStatus, '2026-09-19T02:00:00.000Z');
    Assert.IsTrue(lCache.TryGetStatus(cRoot, lRestored));
    Assert.AreEqual('main', lRestored.Branch, 'Failure must retain the successful observation');
    Assert.AreEqual(4, lRestored.Behind);
    Assert.AreEqual('2026-09-18T01:00:00.000Z', lRestored.LastAnalyzedUtc);
    Assert.IsTrue(lRestored.ScanFailed);
    Assert.AreEqual('root unavailable', lRestored.ScanError);
    Assert.IsTrue(lRestored.HasProblem);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    Assert.IsTrue(lLoaded.LoadFromFile(lPath, lError), lError);
    Assert.IsTrue(lLoaded.TryGetStatus(cRoot, lRestored));
    Assert.AreEqual('2026-09-18T01:00:00.000Z', lRestored.LastAnalyzedUtc);
    Assert.AreEqual('root unavailable', lRestored.ScanError);
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := cRoot;
    lStatus.Branch := 'recovered';
    lLoaded.StoreStatus(lStatus, '2026-09-19T03:00:00.000Z');
    Assert.IsTrue(lLoaded.TryGetStatus(cRoot, lRestored));
    Assert.IsFalse(lRestored.ScanFailed);
    Assert.AreEqual('', lRestored.ScanError);
    Assert.AreEqual('recovered', lRestored.Branch);
    Assert.AreEqual('2026-09-19T03:00:00.000Z', lRestored.LastAnalyzedUtc);
    Assert.IsFalse(lRestored.IsCached);
  finally
    TFile.Delete(lPath);
  end;
end;

procedure TRepoCacheTests.Snapshot_RoundTripsUnavailableRootAndFetchMetadata;
const
  cRoot = 'Z:\Unavailable\RepoOne';
  cObserved = '2026-09-19T12:34:56.000Z';
var
  g: TGarbos;
  lCache, lLoaded: TRepoCache;
  lStatus, lRestored: TRepoStatus;
  lUpdate: TRepoCacheUpdate;
  lEntry: TRepoCacheEntry;
  lInventory: TArray<string>;
  lPath, lError: string;
begin
  GC(lCache, TRepoCache.Create, g);
  GC(lLoaded, TRepoCache.Create, g);
  lPath := TPath.GetTempFileName;
  try
    lCache.SetInventory('old-filter', [cRoot]);
    Assert.IsFalse(lCache.TryGetStatus(cRoot, lRestored));
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := cRoot;
    lStatus.Branch := 'feature/cache';
    lStatus.Behind := 3;
    lStatus.Ahead := 2;
    lStatus.IsDirty := True;
    lStatus.FetchFailed := True;
    lStatus.FetchError := 'remote offline';
    lStatus.LastPullError := 'session-only pull';
    lStatus.LastPushError := 'session-only push';
    lCache.StoreStatus(lStatus, cObserved);
    Assert.IsTrue(lCache.TryGetStatus(cRoot, lRestored), 'Stored analysis must be available');
    Assert.AreEqual(cObserved, lRestored.LastAnalyzedUtc);
    Assert.IsFalse(lRestored.IsCached);
    lUpdate := Default(TRepoCacheUpdate);
    lUpdate.Key := cRoot;
    lUpdate.LastFetchUtc := '2026-09-18T01:00:00.000Z';
    lUpdate.HasLastFetchOk := True;
    lUpdate.LastFetchOk := True;
    lCache.ApplyUpdate(lUpdate);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    Assert.IsTrue(lLoaded.LoadFromFile(lPath, lError), lError);
    lInventory := lLoaded.GetInventory;
    Assert.AreEqual(1, Length(lInventory));
    Assert.AreEqual(cRoot, lInventory[0]);
    Assert.IsTrue(lLoaded.TryGetStatus(cRoot, lRestored));
    Assert.AreEqual(cRoot, lRestored.RepoRoot);
    Assert.AreEqual(cObserved, lRestored.LastAnalyzedUtc);
    Assert.IsTrue(lRestored.IsCached);
    Assert.AreEqual('feature/cache', lRestored.Branch);
    Assert.AreEqual(3, lRestored.Behind);
    Assert.AreEqual(2, lRestored.Ahead);
    Assert.IsTrue(lRestored.IsDirty);
    Assert.IsTrue(lRestored.FetchFailed);
    Assert.AreEqual('remote offline', lRestored.FetchError);
    Assert.AreEqual('', lRestored.LastPullError);
    Assert.AreEqual('', lRestored.LastPushError);
    Assert.IsTrue(lLoaded.TryGet(cRoot, lEntry));
    Assert.AreEqual(lUpdate.LastFetchUtc, lEntry.LastFetchUtc);
    Assert.IsTrue(lEntry.LastFetchOk);
  finally
    TFile.Delete(lPath);
  end;
end;

procedure TRepoCacheTests.Load_InvalidCachePreventsOverwrite;
begin
  AssertRejectedCache('{broken');
end;

procedure TRepoCacheTests.Load_UnsupportedVersionPreventsOverwrite(const aVersion: Integer);
begin
  AssertRejectedCache(Format('{"version":%d,"repos":{}}', [aVersion]));
end;

procedure TRepoCacheTests.Load_EmptyCachePreventsOverwrite;
begin
  AssertRejectedCache('');
end;

procedure TRepoCacheTests.AssertRejectedCache(const aJson: string);
var
  lCache: TRepoCache;
  lError: string;
  lPath: string;
  lOriginal: TBytes;
  lSaved: TBytes;
begin
  lPath := TPath.GetTempFileName;
  lCache := TRepoCache.Create;
  try
    TFile.WriteAllText(lPath, aJson, TEncoding.UTF8);
    lOriginal := TFile.ReadAllBytes(lPath);
    Assert.IsFalse(lCache.LoadFromFile(lPath, lError), 'Invalid cache must be reported');
    Assert.IsNotEmpty(lError);
    Assert.IsFalse(lCache.SaveToFile(lPath, 3600, lError), 'Failed load must prevent overwrite');
    Assert.IsNotEmpty(lError);
    lSaved := TFile.ReadAllBytes(lPath);
    Assert.AreEqual(Length(lOriginal), Length(lSaved));
    Assert.IsTrue(CompareMem(Pointer(lOriginal), Pointer(lSaved), Length(lOriginal)),
      'Original invalid cache bytes must survive');
  finally
    lCache.Free;
    TFile.Delete(lPath);
  end;
end;

function TRepoCacheTests.CreateRepository(const aParent, aName: string): string;
begin
  Result := TPath.Combine(aParent, aName);
  ForceDirectories(TPath.Combine(Result, '.git'));
end;

procedure TRepoCacheTests.BuildScanFingerprint_ChangesWithDiscoverySettings;
var
  lBase: string;
begin
  lBase := TRepoCache.BuildScanFingerprint(['F:\projects'], '*', 10, 'bin');
  Assert.AreNotEqual(lBase, TRepoCache.BuildScanFingerprint(['F:\work'], '*', 10, 'bin'));
  Assert.AreNotEqual(lBase, TRepoCache.BuildScanFingerprint(['F:\projects'], 'Repo*', 10, 'bin'));
  Assert.AreNotEqual(lBase, TRepoCache.BuildScanFingerprint(['F:\projects'], '*', 11, 'bin'));
  Assert.AreNotEqual(lBase, TRepoCache.BuildScanFingerprint(['F:\projects'], '*', 10, 'obj'));
end;

procedure TRepoCacheTests.BuildScanFingerprint_NormalizesEquivalentSettings;
var
  lFirst: string;
  lSecond: string;
begin
  lFirst := TRepoCache.BuildScanFingerprint(['F:\Projects\', 'D:\Work'], ' Repo* ', 10, 'bin'#13#10);
  lSecond := TRepoCache.BuildScanFingerprint(['d:\work\', 'f:\projects'], 'repo*', 10, 'bin'#10);
  Assert.AreEqual(lFirst, lSecond);
  Assert.IsNotEmpty(lFirst);
end;

procedure TRepoCacheTests.GetValidInventory_RejectsFingerprintMismatchAndStaleRoots;
var
  lCache: TRepoCache;
  lRoot: string;
  lRepoRoot: string;
  lInventory: TArray<string>;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseCache-' + TPath.GetRandomFileName);
  ForceDirectories(lRoot);
  try
    lRepoRoot := CreateRepository(lRoot, 'RepoOne');
    lCache := TRepoCache.Create;
    try
      lCache.SetInventory('expected', [lRepoRoot, TPath.Combine(lRoot, 'Missing')]);
      Assert.AreEqual(0, Length(lCache.GetValidInventory('other')));
      lInventory := lCache.GetValidInventory('expected');
      Assert.AreEqual(1, Length(lInventory));
      Assert.AreEqual(lRepoRoot, lInventory[0]);
      TDirectory.Delete(lRepoRoot, True);
      Assert.AreEqual(0, Length(lCache.GetValidInventory('expected')));
    finally
      lCache.Free;
    end;
  finally
    if DirectoryExists(lRoot) then
      TDirectory.Delete(lRoot, True);
  end;
end;

procedure TRepoCacheTests.Load_VersionOneHasNoInventory;
var
  lCache: TRepoCache;
  lError: string;
  lPath: string;
begin
  lPath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(lPath, '{"version":1,"repos":{}}', TEncoding.UTF8);
    lCache := TRepoCache.Create;
    try
      Assert.IsTrue(lCache.LoadFromFile(lPath, lError), lError);
      Assert.AreEqual(0, Length(lCache.GetValidInventory('anything')));
    finally
      lCache.Free;
    end;
  finally
    if FileExists(lPath) then
      TFile.Delete(lPath);
  end;
end;

procedure TRepoCacheTests.Save_WritesVersionThree;
var
  lCache: TRepoCache;
  lError: string;
  lJson: string;
  lPath: string;
begin
  lPath := TPath.GetTempFileName;
  lCache := TRepoCache.Create;
  try
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    lJson := TFile.ReadAllText(lPath, TEncoding.UTF8);
    Assert.Contains(lJson, '"version":3');
  finally
    lCache.Free;
    if FileExists(lPath) then
      TFile.Delete(lPath);
  end;
end;

procedure TRepoCacheTests.SaveAndLoad_RoundTripsInventory;
var
  lCache: TRepoCache;
  lLoaded: TRepoCache;
  lError: string;
  lInventory: TArray<string>;
  lPath: string;
  lRepoRoot: string;
  lRoot: string;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseCache-' + TPath.GetRandomFileName);
  ForceDirectories(lRoot);
  lPath := TPath.Combine(lRoot, 'cache.json');
  try
    lRepoRoot := CreateRepository(lRoot, 'RepoOne');
    lCache := TRepoCache.Create;
    try
      lCache.SetInventory('fingerprint-one', [lRepoRoot]);
      Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    finally
      lCache.Free;
    end;

    lLoaded := TRepoCache.Create;
    try
      Assert.IsTrue(lLoaded.LoadFromFile(lPath, lError), lError);
      lInventory := lLoaded.GetValidInventory('fingerprint-one');
      Assert.AreEqual(1, Length(lInventory));
      Assert.AreEqual(lRepoRoot, lInventory[0]);
    finally
      lLoaded.Free;
    end;
  finally
    if DirectoryExists(lRoot) then
      TDirectory.Delete(lRoot, True);
  end;
end;

procedure TRepoCacheTests.UnsavedInventory_DoesNotReplaceLastGoodFile;
var
  lCache: TRepoCache;
  lLoaded: TRepoCache;
  lError: string;
  lInventory: TArray<string>;
  lPath: string;
  lRepoOne: string;
  lRepoTwo: string;
  lRoot: string;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseCache-' + TPath.GetRandomFileName);
  ForceDirectories(lRoot);
  lPath := TPath.Combine(lRoot, 'cache.json');
  try
    lRepoOne := CreateRepository(lRoot, 'RepoOne');
    lRepoTwo := CreateRepository(lRoot, 'RepoTwo');
    lCache := TRepoCache.Create;
    try
      lCache.SetInventory('old', [lRepoOne]);
      Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
      lCache.SetInventory('new', [lRepoTwo]);
    finally
      lCache.Free;
    end;

    lLoaded := TRepoCache.Create;
    try
      Assert.IsTrue(lLoaded.LoadFromFile(lPath, lError), lError);
      lInventory := lLoaded.GetValidInventory('old');
      Assert.AreEqual(1, Length(lInventory));
      Assert.AreEqual(lRepoOne, lInventory[0]);
      Assert.AreEqual(0, Length(lLoaded.GetValidInventory('new')));
    finally
      lLoaded.Free;
    end;
  finally
    if DirectoryExists(lRoot) then
      TDirectory.Delete(lRoot, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRepoCacheTests);

end.
