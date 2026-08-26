unit TestAppSettings;

interface

uses
  System.IOUtils, System.SysUtils,

  DUnitX.TestFramework,
  UAppSettings;

type
  [TestFixture]
  TAppSettingsTests = class
  public
    [Test]
    procedure Create_DefaultsRepositoryFilterToWildcard;
    [Test]
    procedure Create_DefaultsCacheTtlToOneHour;
    [Test]
    procedure Load_LegacyStartPathMigratesToScanPaths;
    [Test]
    procedure SaveAndLoad_PreservesAllScanPaths;
  end;

implementation

procedure TAppSettingsTests.Create_DefaultsCacheTtlToOneHour;
var
  lSettings: TAppSettings;
begin
  lSettings := TAppSettings.Create;
  try
    Assert.AreEqual(3600, lSettings.CacheTtlSeconds);
  finally
    lSettings.Free;
  end;
end;

procedure TAppSettingsTests.Create_DefaultsRepositoryFilterToWildcard;
var
  lSettings: TAppSettings;
begin
  lSettings := TAppSettings.Create;
  try
    Assert.AreEqual('*', lSettings.TargetRepoName);
    Assert.AreEqual(1, Length(lSettings.RepoNameHistory));
    Assert.AreEqual('*', lSettings.RepoNameHistory[0]);
  finally
    lSettings.Free;
  end;
end;

procedure TAppSettingsTests.SaveAndLoad_PreservesAllScanPaths;
var
  lSettings: TAppSettings;
  lLoaded: TAppSettings;
  lSettingsPath: string;
  lExistingBytes: TBytes;
  lHadFile: Boolean;
begin
  lSettingsPath := TAppSettings.GetSettingsFilePath;
  lHadFile := FileExists(lSettingsPath);
  if lHadFile then
    lExistingBytes := TFile.ReadAllBytes(lSettingsPath);
  try
    lSettings := TAppSettings.Create;
    try
      lSettings.ScanPaths := ['F:\projects', 'D:\work'];
      lSettings.CacheTtlSeconds := 300;
      lSettings.Save;
    finally
      lSettings.Free;
    end;

    lLoaded := TAppSettings.Create;
    try
      lLoaded.Load;
      Assert.AreEqual(2, Length(lLoaded.ScanPaths));
      Assert.AreEqual('F:\projects', lLoaded.ScanPaths[0]);
      Assert.AreEqual('D:\work', lLoaded.ScanPaths[1]);
      Assert.AreEqual(300, lLoaded.CacheTtlSeconds);
    finally
      lLoaded.Free;
    end;
  finally
    if lHadFile then
      TFile.WriteAllBytes(lSettingsPath, lExistingBytes)
    else if FileExists(lSettingsPath) then
      TFile.Delete(lSettingsPath);
  end;
end;

procedure TAppSettingsTests.Load_LegacyStartPathMigratesToScanPaths;
var
  lSettings: TAppSettings;
  lSettingsPath: string;
  lLegacyRoot: string;
  lExistingBytes: TBytes;
  lHadFile: Boolean;
begin
  lSettingsPath := TAppSettings.GetSettingsFilePath;
  lLegacyRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseLegacyRoot');
  lHadFile := FileExists(lSettingsPath);
  if lHadFile then
    lExistingBytes := TFile.ReadAllBytes(lSettingsPath);
  try
    TFile.WriteAllText(lSettingsPath, '[Scan]'#13#10 + 'StartPath=' + lLegacyRoot + #13#10 +
      'TargetRepoName=maxlogicfoundation'#13#10);
    lSettings := TAppSettings.Create;
    try
      lSettings.Load;
      Assert.AreEqual(1, Length(lSettings.ScanPaths));
      Assert.AreEqual(lLegacyRoot, lSettings.ScanPaths[0]);
      Assert.AreEqual('*', lSettings.TargetRepoName);
    finally
      lSettings.Free;
    end;
  finally
    if lHadFile then
      TFile.WriteAllBytes(lSettingsPath, lExistingBytes)
    else if FileExists(lSettingsPath) then
      TFile.Delete(lSettingsPath);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAppSettingsTests);

end.
