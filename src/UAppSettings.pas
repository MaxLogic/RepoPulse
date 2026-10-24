unit UAppSettings;

interface

uses
  System.Classes, System.IniFiles, System.IOUtils, System.SysUtils,

  Winapi.Windows,

  AutoFree, maxLogic.ioutils,
  UFolderSelection;

type
  TAppSettings = class
  private
    fStartPath: string;
    fScanPaths: TArray<string>;
    fMaxDepth: Integer;
    fExcludeDirs: TArray<string>;
    fRepositoryExclusions: TArray<string>;
    fStatusFilterIndex: Integer;
    fThrottleLimit: Integer;
    fActionThrottleLimit: Integer;
    fCacheTtlSeconds: Integer;
    fDebugLogEnabled: Boolean;
    fDebugLogPath: string;
    fTargetRepoName: string;
    fRepoNameHistory: TArray<string>;
    fFolderSelectionRules: TArray<TFolderSelectionRule>;
    fExpandedFolders: TArray<string>;
    fFoldersPaneWidth: Integer;
    fFolderSelectionMigrated: Boolean;
    procedure LoadFolderSelection(const aIni: TMemIniFile);
    class function DefaultExcludeDirs: TArray<string>; static;
    class function GetExeFolder: string; static;
    class function GetLegacySettingsFolder: string; static;
    class function GetLegacySettingsFilePath: string; static;
  public
    constructor Create;
    procedure Load;
    procedure Save;
    class function GetSettingsFolder: string; static;
    class function GetSettingsFilePath: string; static;
    property StartPath: string read fStartPath write fStartPath;
    property ScanPaths: TArray<string> read fScanPaths write fScanPaths;
    property MaxDepth: Integer read fMaxDepth write fMaxDepth;
    property ExcludeDirs: TArray<string> read fExcludeDirs write fExcludeDirs;
    property RepositoryExclusions: TArray<string> read fRepositoryExclusions write fRepositoryExclusions;
    property StatusFilterIndex: Integer read fStatusFilterIndex write fStatusFilterIndex;
    property ThrottleLimit: Integer read fThrottleLimit write fThrottleLimit;
    property ActionThrottleLimit: Integer read fActionThrottleLimit write fActionThrottleLimit;
    property CacheTtlSeconds: Integer read fCacheTtlSeconds write fCacheTtlSeconds;
    property DebugLogEnabled: Boolean read fDebugLogEnabled write fDebugLogEnabled;
    property DebugLogPath: string read fDebugLogPath write fDebugLogPath;
    property TargetRepoName: string read fTargetRepoName write fTargetRepoName;
    property RepoNameHistory: TArray<string> read fRepoNameHistory write fRepoNameHistory;
    property FolderSelectionRules: TArray<TFolderSelectionRule> read fFolderSelectionRules write fFolderSelectionRules;
    property ExpandedFolders: TArray<string> read fExpandedFolders write fExpandedFolders;
    property FoldersPaneWidth: Integer read fFoldersPaneWidth write fFoldersPaneWidth;
    property FolderSelectionMigrated: Boolean read fFolderSelectionMigrated;
  end;

implementation

const
  cSectionScan = 'Scan';
  cSectionDebug = 'Debug';
  cSectionHistory = 'History';
  cSectionFolders = 'Folders';
  cKeyFolderVersion = 'Version';
  cKeyFolderRuleCount = 'RuleCount';
  cKeyFolderPath = 'Path';
  cKeyFolderIncluded = 'Included';
  cKeyExpandedFolders = 'ExpandedFolders';
  cKeyFoldersPaneWidth = 'PaneWidth';

  cKeyStartPath = 'StartPath';
  cKeyScanPaths = 'ScanPaths';
  cKeyMaxDepth = 'MaxDepth';
  cKeyExcludeDirs = 'ExcludeDirs';
  cKeyRepositoryExclusions = 'RepositoryExclusions';
  cKeyStatusFilterIndex = 'StatusFilterIndex';
  cKeyThrottleLimit = 'ThrottleLimit';
  cKeyActionThrottleLimit = 'ActionThrottleLimit';
  cKeyCacheTtlSeconds = 'CacheTtlSeconds';
  cKeyDebugLogEnabled = 'DebugLogEnabled';
  cKeyDebugLogPath = 'DebugLogPath';
  cKeyTargetRepoName = 'TargetRepoName';
  cKeyRepoNameHistory = 'RepoNameHistory';
  cLegacyDefaultRepoName = 'maxlogicfoundation';

class function TAppSettings.DefaultExcludeDirs: TArray<string>;
begin
  Result := ['.git', 'node_modules', 'bin', 'obj', '.vs', '.idea'];
end;

constructor TAppSettings.Create;
begin
  inherited Create;
  fStartPath := GetCurrentDir;
  fScanPaths := [fStartPath];
  fMaxDepth := 10;
  fExcludeDirs := DefaultExcludeDirs;
  fThrottleLimit := 6;
  fActionThrottleLimit := 3;
  fCacheTtlSeconds := 3600;
  fDebugLogEnabled := False;
  fDebugLogPath := '';
  fTargetRepoName := '*';
  fRepoNameHistory := ['*'];
  fFoldersPaneWidth := 260;
end;

class function TAppSettings.GetSettingsFilePath: string;
begin
  Result := CombinePath([GetSettingsFolder, 'settings.ini']);
end;

class function TAppSettings.GetSettingsFolder: string;
begin
  Result := GetExeFolder;
end;

class function TAppSettings.GetLegacySettingsFilePath: string;
begin
  Result := CombinePath([GetLegacySettingsFolder, 'settings.ini']);
end;

class function TAppSettings.GetLegacySettingsFolder: string;
var
  lRoot: string;
begin
  lRoot := TPath.GetHomePath;
  Result := CombinePath([lRoot, 'ScanGitRepos']);
end;

class function TAppSettings.GetExeFolder: string;
begin
  Result := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
end;

procedure TAppSettings.LoadFolderSelection(const aIni: TMemIniFile);
var
  g: TGarbos;
  lList: TStringList;
  lVersion, lCount: Integer;
  lPath: string;
  i: Integer;
begin
  lVersion := 0;
  if Assigned(aIni) then
    lVersion := aIni.ReadInteger(cSectionFolders, cKeyFolderVersion, 0);
  fFolderSelectionRules := [];
  fFolderSelectionMigrated := lVersion = 0;
  if fFolderSelectionMigrated then
  begin
    for lPath in fScanPaths do
      fFolderSelectionRules := SetFolderSelection(lPath, True, fFolderSelectionRules);
    Exit;
  end;

  lCount := aIni.ReadInteger(cSectionFolders, cKeyFolderRuleCount, 0);
  if lCount < 0 then
    lCount := 0;
  SetLength(fFolderSelectionRules, lCount);
  for i := 0 to lCount - 1 do
  begin
    fFolderSelectionRules[i].Path := NormalizeSelectionPath(
      aIni.ReadString(cSectionFolders, cKeyFolderPath + IntToStr(i), ''));
    fFolderSelectionRules[i].Included := aIni.ReadBool(cSectionFolders,
      cKeyFolderIncluded + IntToStr(i), False);
  end;
  GC(lList, TStringList.Create, g);
  lList.StrictDelimiter := True;
  lList.CommaText := aIni.ReadString(cSectionFolders, cKeyExpandedFolders, '');
  fExpandedFolders := lList.ToStringArray;
  fFoldersPaneWidth := aIni.ReadInteger(cSectionFolders, cKeyFoldersPaneWidth, 260);
end;

procedure TAppSettings.Load;
var
  g: TGarbos;
  lIni: TMemIniFile;
  lList: TStringList;
  lValue: string;
  i: Integer;
  lFilePath: string;
  lLegacyPath: string;
begin
  lFilePath := GetSettingsFilePath;
  if not FileExists(lFilePath) then
  begin
    lLegacyPath := GetLegacySettingsFilePath;
    if FileExists(lLegacyPath) then
      lFilePath := lLegacyPath;
  end;

  if not FileExists(lFilePath) then
  begin
    LoadFolderSelection(nil);
    Exit;
  end;

  GC(lIni, TMemIniFile.Create(lFilePath), g);

  fStartPath := lIni.ReadString(cSectionScan, cKeyStartPath, fStartPath);
  lValue := lIni.ReadString(cSectionScan, cKeyScanPaths, '');
  if lValue <> '' then
  begin
    GC(lList, TStringList.Create, g);
    lList.StrictDelimiter := True;
    lList.CommaText := lValue;
    SetLength(fScanPaths, lList.Count);
    for i := 0 to lList.Count - 1 do
      fScanPaths[i] := lList[i];
  end else begin
    fScanPaths := [fStartPath];
  end;
  if Length(fScanPaths) = 0 then
    fScanPaths := [fStartPath];
  fStartPath := fScanPaths[0];
  fMaxDepth := lIni.ReadInteger(cSectionScan, cKeyMaxDepth, fMaxDepth);
  fThrottleLimit := lIni.ReadInteger(cSectionScan, cKeyThrottleLimit, fThrottleLimit);
  fActionThrottleLimit := lIni.ReadInteger(cSectionScan, cKeyActionThrottleLimit,
    fActionThrottleLimit);
  fCacheTtlSeconds := lIni.ReadInteger(cSectionScan, cKeyCacheTtlSeconds, fCacheTtlSeconds);
  fTargetRepoName := lIni.ReadString(cSectionScan, cKeyTargetRepoName, fTargetRepoName);
  fStatusFilterIndex := lIni.ReadInteger(cSectionScan, cKeyStatusFilterIndex, 0);
  if (Trim(fTargetRepoName) = '') or SameText(Trim(fTargetRepoName), cLegacyDefaultRepoName) then
    fTargetRepoName := '*';
  fDebugLogEnabled := lIni.ReadBool(cSectionDebug, cKeyDebugLogEnabled, fDebugLogEnabled);
  fDebugLogPath := lIni.ReadString(cSectionDebug, cKeyDebugLogPath, fDebugLogPath);

  lValue := lIni.ReadString(cSectionScan, cKeyExcludeDirs, '');
  if lValue <> '' then
  begin
    GC(lList, TStringList.Create, g);
    lList.StrictDelimiter := True;
    lList.CommaText := lValue;
    SetLength(fExcludeDirs, lList.Count);
    for i := 0 to lList.Count - 1 do
      fExcludeDirs[i] := lList[i];
  end;

  GC(lList, TStringList.Create, g);
  lList.StrictDelimiter := True;
  lList.CommaText := lIni.ReadString(cSectionScan, cKeyRepositoryExclusions, '');
  SetLength(fRepositoryExclusions, lList.Count);
  for i := 0 to lList.Count - 1 do
    fRepositoryExclusions[i] := lList[i];

  lValue := lIni.ReadString(cSectionHistory, cKeyRepoNameHistory, '');
  if lValue <> '' then
  begin
    GC(lList, TStringList.Create, g);
    lList.StrictDelimiter := True;
    lList.CommaText := lValue;
    SetLength(fRepoNameHistory, lList.Count);
    for i := 0 to lList.Count - 1 do
      fRepoNameHistory[i] := lList[i];
  end;
  LoadFolderSelection(lIni);
end;

procedure TAppSettings.Save;
var
  g: TGarbos;
  lIni: TMemIniFile;
  lList: TStringList;
  i: Integer;
  lFilePath: string;
  lTempPath: string;
begin
  if not DirectoryExists(GetSettingsFolder) then
    ForceDirectories(GetSettingsFolder);

  lFilePath := GetSettingsFilePath;
  lTempPath := lFilePath + '.tmp';

  GC(lIni, TMemIniFile.Create(lTempPath, TEncoding.Unicode), g);

  if Length(fScanPaths) > 0 then
    fStartPath := fScanPaths[0];
  lIni.WriteString(cSectionScan, cKeyStartPath, fStartPath);
  lIni.WriteInteger(cSectionScan, cKeyMaxDepth, fMaxDepth);
  lIni.WriteInteger(cSectionScan, cKeyThrottleLimit, fThrottleLimit);
  lIni.WriteInteger(cSectionScan, cKeyActionThrottleLimit, fActionThrottleLimit);
  lIni.WriteInteger(cSectionScan, cKeyCacheTtlSeconds, fCacheTtlSeconds);
  lIni.WriteString(cSectionScan, cKeyTargetRepoName, fTargetRepoName);
  lIni.WriteInteger(cSectionScan, cKeyStatusFilterIndex, fStatusFilterIndex);
  lIni.WriteBool(cSectionDebug, cKeyDebugLogEnabled, fDebugLogEnabled);
  lIni.WriteString(cSectionDebug, cKeyDebugLogPath, fDebugLogPath);

  GC(lList, TStringList.Create, g);
  lList.StrictDelimiter := True;
  lList.Clear;
  for i := 0 to Length(fScanPaths) - 1 do
    lList.Add(fScanPaths[i]);
  lIni.WriteString(cSectionScan, cKeyScanPaths, lList.CommaText);

  lList.Clear;
  for i := 0 to Length(fExcludeDirs) - 1 do
    lList.Add(fExcludeDirs[i]);
  lIni.WriteString(cSectionScan, cKeyExcludeDirs, lList.CommaText);

  lList.Clear;
  for i := 0 to Length(fRepositoryExclusions) - 1 do
    lList.Add(fRepositoryExclusions[i]);
  lIni.WriteString(cSectionScan, cKeyRepositoryExclusions, lList.CommaText);

  lList.Clear;
  for i := 0 to Length(fRepoNameHistory) - 1 do
    lList.Add(fRepoNameHistory[i]);
  lIni.WriteString(cSectionHistory, cKeyRepoNameHistory, lList.CommaText);

  lIni.EraseSection(cSectionFolders);
  lIni.WriteInteger(cSectionFolders, cKeyFolderVersion, 1);
  lIni.WriteInteger(cSectionFolders, cKeyFolderRuleCount, Length(fFolderSelectionRules));
  for i := 0 to High(fFolderSelectionRules) do
  begin
    lIni.WriteString(cSectionFolders, cKeyFolderPath + IntToStr(i),
      NormalizeSelectionPath(fFolderSelectionRules[i].Path));
    lIni.WriteBool(cSectionFolders, cKeyFolderIncluded + IntToStr(i),
      fFolderSelectionRules[i].Included);
  end;
  lList.Clear;
  lList.AddStrings(fExpandedFolders);
  lIni.WriteString(cSectionFolders, cKeyExpandedFolders, lList.CommaText);
  lIni.WriteInteger(cSectionFolders, cKeyFoldersPaneWidth, fFoldersPaneWidth);

  try
    lIni.UpdateFile;
    if not MoveFileEx(PChar(lTempPath), PChar(lFilePath), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  except
    on E: Exception do
    begin
      if FileExists(lTempPath) then
        TFile.Delete(lTempPath);
      raise;
    end;
  end;
end;

end.
