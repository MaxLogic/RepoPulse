unit TestRepoCache;

interface

uses
  System.IOUtils, System.SysUtils,

  DUnitX.TestFramework,
  URepoCache;

type
  [TestFixture]
  TRepoCacheTests = class
  private
    function CreateRepository(const aParent, aName: string): string;
  public
    [Test]
    procedure BuildScanFingerprint_NormalizesEquivalentSettings;
    [Test]
    procedure BuildScanFingerprint_ChangesWithDiscoverySettings;
    [Test]
    procedure GetValidInventory_RejectsFingerprintMismatchAndStaleRoots;
    [Test]
    procedure Load_VersionOneHasNoInventory;
    [Test]
    procedure Save_WritesVersionTwo;
    [Test]
    procedure SaveAndLoad_RoundTripsInventory;
    [Test]
    procedure UnsavedInventory_DoesNotReplaceLastGoodFile;
  end;

implementation

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

procedure TRepoCacheTests.Save_WritesVersionTwo;
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
    Assert.Contains(lJson, '"version":2');
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
