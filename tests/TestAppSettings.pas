unit TestAppSettings;

interface

uses
  System.IniFiles, System.IOUtils, System.SysUtils,

  AutoFree, DUnitX.TestFramework,
  UAppSettings, UFolderSelection;

type
  [TestFixture]
  TAppSettingsTests = class
  public
    [Test]
    procedure Create_DefaultsRepositoryFilterToWildcard;
    [Test]
    procedure Create_DefaultsCacheTtlToOneHour;
    [Test]
    procedure Save_DefaultsPullPushThrottleToThree;
    [Test]
    procedure Load_LegacyStartPathMigratesToScanPaths;
    [Test]
    procedure SaveAndLoad_PreservesAllScanPaths;
    [Test]
    procedure SaveAndLoad_PreservesRepositoryExclusionsSeparately;
    [TestCase('Long list', 'True')]
    [TestCase('Unicode', 'False')]
    procedure SaveAndLoad_PreservesLongAndUnicodeExclusions(const aLongList: Boolean);
    [Test]
    procedure Create_DefaultsFoldersPaneWidth;
    [Test]
    procedure Load_MigratesLegacyFolderSelectionOnce;
    [Test]
    procedure SaveAndLoad_PreservesFolderRulesAndLayout;
  end;

implementation

procedure TAppSettingsTests.Create_DefaultsFoldersPaneWidth;
var
  g: TGarbos;
  lSettings: TAppSettings;
begin
  GC(lSettings, TAppSettings.Create, g);
  Assert.AreEqual(260, lSettings.FoldersPaneWidth);
  Assert.IsFalse(lSettings.FolderSelectionMigrated);
end;

procedure TAppSettingsTests.Load_MigratesLegacyFolderSelectionOnce;
var
  g: TGarbos;
  lSettings, lReloaded: TAppSettings;
  lSettingsPath: string;
  lExistingBytes: TBytes;
  lHadFile: Boolean;
begin
  lSettingsPath := TAppSettings.GetSettingsFilePath;
  lHadFile := FileExists(lSettingsPath);
  if lHadFile then
    lExistingBytes := TFile.ReadAllBytes(lSettingsPath);
  try
    TFile.WriteAllText(lSettingsPath, '[Scan]'#13#10 +
      'ScanPaths=Z:\Unavailable\Child,Z:\Unavailable,\\server\share\offline'#13#10);
    GC(lSettings, TAppSettings.Create, g);
    lSettings.Load;
    Assert.IsTrue(lSettings.FolderSelectionMigrated);
    Assert.AreEqual(2, Length(lSettings.FolderSelectionRules));
    Assert.IsTrue(EvaluateFolderSelection('Z:\Unavailable\Child', lSettings.FolderSelectionRules));
    Assert.IsTrue(EvaluateFolderSelection('\\server\share\offline\child', lSettings.FolderSelectionRules));
    Assert.IsFalse(EvaluateFolderSelection('Z:\Elsewhere', lSettings.FolderSelectionRules));
    lSettings.FolderSelectionRules := [];
    lSettings.Save;
    GC(lReloaded, TAppSettings.Create, g);
    lReloaded.Load;
    Assert.IsFalse(lReloaded.FolderSelectionMigrated);
    Assert.AreEqual(0, Length(lReloaded.FolderSelectionRules), 'Explicit select-none must not remigrate');
    Assert.AreEqual(3, Length(lReloaded.ScanPaths), 'Migration preserves legacy settings');
  finally
    if lHadFile then
      TFile.WriteAllBytes(lSettingsPath, lExistingBytes)
    else if FileExists(lSettingsPath) then
      TFile.Delete(lSettingsPath);
  end;
end;

procedure TAppSettingsTests.SaveAndLoad_PreservesFolderRulesAndLayout;
var
  g: TGarbos;
  lSettings, lLoaded: TAppSettings;
  lSettingsPath: string;
  lExistingBytes: TBytes;
  lHadFile: Boolean;
  lRules: TArray<TFolderSelectionRule>;
begin
  lSettingsPath := TAppSettings.GetSettingsFilePath;
  lHadFile := FileExists(lSettingsPath);
  if lHadFile then
    lExistingBytes := TFile.ReadAllBytes(lSettingsPath);
  try
    GC(lSettings, TAppSettings.Create, g);
    GC(lLoaded, TAppSettings.Create, g);
    SetLength(lRules, 3);
    lRules[0].Path := 'Z:/Unavailable/';
    lRules[0].Included := True;
    lRules[1].Path := 'Z:\Unavailable\zażółć';
    lRules[1].Included := False;
    lRules[2].Path := 'Z:\Unavailable\zażółć\Данные';
    lRules[2].Included := True;
    lSettings.FolderSelectionRules := lRules;
    lSettings.ExpandedFolders := ['Z:\Unavailable', '\\server\share\Данные'];
    lSettings.FoldersPaneWidth := 340;
    lSettings.Save;
    lLoaded.Load;
    Assert.AreEqual(3, Length(lLoaded.FolderSelectionRules));
    Assert.AreEqual('z:\unavailable', lLoaded.FolderSelectionRules[0].Path);
    Assert.IsTrue(EvaluateFolderSelection('Z:\Unavailable\Other', lLoaded.FolderSelectionRules));
    Assert.IsFalse(EvaluateFolderSelection('Z:\Unavailable\zażółć\Other', lLoaded.FolderSelectionRules));
    Assert.IsTrue(EvaluateFolderSelection('Z:\Unavailable\zażółć\Данные\Child', lLoaded.FolderSelectionRules));
    Assert.AreEqual(2, Length(lLoaded.ExpandedFolders));
    Assert.AreEqual('Z:\Unavailable', lLoaded.ExpandedFolders[0]);
    Assert.AreEqual('\\server\share\Данные', lLoaded.ExpandedFolders[1]);
    Assert.AreEqual(340, lLoaded.FoldersPaneWidth);
    Assert.IsFalse(lLoaded.FolderSelectionMigrated);
  finally
    if lHadFile then
      TFile.WriteAllBytes(lSettingsPath, lExistingBytes)
    else if FileExists(lSettingsPath) then
      TFile.Delete(lSettingsPath);
  end;
end;

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
    Assert.AreEqual(0, Length(lSettings.RepositoryExclusions));
  finally
    lSettings.Free;
  end;
end;

procedure TAppSettingsTests.Save_DefaultsPullPushThrottleToThree;
var
  lExistingBytes: TBytes;
  lHadFile: Boolean;
  lIni: TIniFile;
  lSettings: TAppSettings;
  lSettingsPath: string;
begin
  lSettingsPath := TAppSettings.GetSettingsFilePath;
  lHadFile := FileExists(lSettingsPath);
  if lHadFile then
    lExistingBytes := TFile.ReadAllBytes(lSettingsPath);
  try
    lSettings := TAppSettings.Create;
    try
      lSettings.Save;
    finally
      lSettings.Free;
    end;

    lIni := TIniFile.Create(lSettingsPath);
    try
      Assert.AreEqual(3, lIni.ReadInteger('Scan', 'ActionThrottleLimit', -1));
    finally
      lIni.Free;
    end;
  finally
    if lHadFile then
      TFile.WriteAllBytes(lSettingsPath, lExistingBytes)
    else if FileExists(lSettingsPath) then
      TFile.Delete(lSettingsPath);
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
      lSettings.ActionThrottleLimit := 2;
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
      Assert.AreEqual(2, lLoaded.ActionThrottleLimit);
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

procedure TAppSettingsTests.SaveAndLoad_PreservesRepositoryExclusionsSeparately;
var
  g: TGarbos;
  lSettings: TAppSettings;
  lLoaded: TAppSettings;
  lSettingsPath: string;
  lExistingBytes: TBytes;
  lHadFile: Boolean;
  lPatterns: TArray<string>;
  i: Integer;
begin
  lSettingsPath := TAppSettings.GetSettingsFilePath;
  lHadFile := FileExists(lSettingsPath);
  if lHadFile then
    lExistingBytes := TFile.ReadAllBytes(lSettingsPath);
  try
    GC(lSettings, TAppSettings.Create, g);
    GC(lLoaded, TAppSettings.Create, g);
    lPatterns := ['*-workspace', '*\_obselete\*', '\\Server\Share\Work?\*',
      'F:/Mixed Case/Repo,Archive/*', '', '   ', 'repo"quoted*'];
    lSettings.RepositoryExclusions := lPatterns;
    lSettings.ExcludeDirs := ['.git', 'node_modules'];
    lSettings.Save;
    lLoaded.Load;
    Assert.AreEqual(Length(lPatterns), Length(lLoaded.RepositoryExclusions));
    for i := 0 to High(lPatterns) do
      Assert.AreEqual(lPatterns[i], lLoaded.RepositoryExclusions[i]);
    Assert.AreEqual(2, Length(lLoaded.ExcludeDirs));
    Assert.AreEqual('.git', lLoaded.ExcludeDirs[0]);
    Assert.AreEqual('node_modules', lLoaded.ExcludeDirs[1]);

    lSettings.RepositoryExclusions := [];
    lSettings.Save;
    lLoaded.Load;
    Assert.AreEqual(0, Length(lLoaded.RepositoryExclusions), 'Reload must clear removed rules');
  finally
    if lHadFile then
      TFile.WriteAllBytes(lSettingsPath, lExistingBytes)
    else if FileExists(lSettingsPath) then
      TFile.Delete(lSettingsPath);
  end;
end;

procedure TAppSettingsTests.SaveAndLoad_PreservesLongAndUnicodeExclusions(const aLongList: Boolean);
var
  g: TGarbos;
  lSettings, lLoaded: TAppSettings;
  lSettingsPath: string;
  lExistingBytes: TBytes;
  lHadFile: Boolean;
  lPatterns: TArray<string>;
  i: Integer;
begin
  lSettingsPath := TAppSettings.GetSettingsFilePath;
  lHadFile := FileExists(lSettingsPath);
  if lHadFile then
    lExistingBytes := TFile.ReadAllBytes(lSettingsPath);
  try
    GC(lSettings, TAppSettings.Create, g);
    GC(lLoaded, TAppSettings.Create, g);
    if aLongList then
    begin
      SetLength(lPatterns, 100);
      for i := 0 to High(lPatterns) do
        lPatterns[i] := Format('C:\Repositories\LongFolderNameForExclusionPattern%d\*', [i]);
    end else begin
      lPatterns := ['*zażółć-gęślą-jaźń*', '\\Serwer\Данные\репозиторий\*'];
    end;
    lSettings.RepositoryExclusions := lPatterns;
    lSettings.Save;
    lLoaded.Load;
    Assert.AreEqual(Length(lPatterns), Length(lLoaded.RepositoryExclusions));
    for i := 0 to High(lPatterns) do
      Assert.AreEqual(lPatterns[i], lLoaded.RepositoryExclusions[i]);
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
      Assert.AreEqual(0, Length(lSettings.RepositoryExclusions));
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
