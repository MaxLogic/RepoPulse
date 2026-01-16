unit UAppSettings;

interface

uses
  System.Classes, System.IniFiles, System.IOUtils, System.SysUtils,

  Winapi.Windows,

  AutoFree, maxLogic.ioutils;

type
  TAppSettings = class
  private
    fStartPath: string;
    fMaxDepth: Integer;
    fExcludeDirs: TArray<string>;
    fThrottleLimit: Integer;
    fCacheTtlSeconds: Integer;
    fDebugLogEnabled: Boolean;
    fDebugLogPath: string;
    fTargetRepoName: string;
    fRepoNameHistory: TArray<string>;
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
    property MaxDepth: Integer read fMaxDepth write fMaxDepth;
    property ExcludeDirs: TArray<string> read fExcludeDirs write fExcludeDirs;
    property ThrottleLimit: Integer read fThrottleLimit write fThrottleLimit;
    property CacheTtlSeconds: Integer read fCacheTtlSeconds write fCacheTtlSeconds;
    property DebugLogEnabled: Boolean read fDebugLogEnabled write fDebugLogEnabled;
    property DebugLogPath: string read fDebugLogPath write fDebugLogPath;
    property TargetRepoName: string read fTargetRepoName write fTargetRepoName;
    property RepoNameHistory: TArray<string> read fRepoNameHistory write fRepoNameHistory;
  end;

implementation

const
  cSectionScan = 'Scan';
  cSectionDebug = 'Debug';
  cSectionHistory = 'History';

  cKeyStartPath = 'StartPath';
  cKeyMaxDepth = 'MaxDepth';
  cKeyExcludeDirs = 'ExcludeDirs';
  cKeyThrottleLimit = 'ThrottleLimit';
  cKeyCacheTtlSeconds = 'CacheTtlSeconds';
  cKeyDebugLogEnabled = 'DebugLogEnabled';
  cKeyDebugLogPath = 'DebugLogPath';
  cKeyTargetRepoName = 'TargetRepoName';
  cKeyRepoNameHistory = 'RepoNameHistory';

class function TAppSettings.DefaultExcludeDirs: TArray<string>;
begin
  Result := ['.git', 'node_modules', 'bin', 'obj', '.vs', '.idea'];
end;

constructor TAppSettings.Create;
begin
  inherited Create;
  fStartPath := GetCurrentDir;
  fMaxDepth := 10;
  fExcludeDirs := DefaultExcludeDirs;
  fThrottleLimit := 6;
  fCacheTtlSeconds := 300;
  fDebugLogEnabled := False;
  fDebugLogPath := '';
  fTargetRepoName := 'maxlogicfoundation';
  fRepoNameHistory := ['maxlogicfoundation'];
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

procedure TAppSettings.Load;
var
  g: TGarbos;
  lIni: TIniFile;
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
    Exit;

  GC(lIni, TIniFile.Create(lFilePath), g);

  fStartPath := lIni.ReadString(cSectionScan, cKeyStartPath, fStartPath);
  fMaxDepth := lIni.ReadInteger(cSectionScan, cKeyMaxDepth, fMaxDepth);
  fThrottleLimit := lIni.ReadInteger(cSectionScan, cKeyThrottleLimit, fThrottleLimit);
  fCacheTtlSeconds := lIni.ReadInteger(cSectionScan, cKeyCacheTtlSeconds, fCacheTtlSeconds);
  fTargetRepoName := lIni.ReadString(cSectionScan, cKeyTargetRepoName, fTargetRepoName);
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
end;

procedure TAppSettings.Save;
var
  g: TGarbos;
  lIni: TIniFile;
  lList: TStringList;
  i: Integer;
  lFilePath: string;
  lTempPath: string;
begin
  if not DirectoryExists(GetSettingsFolder) then
    ForceDirectories(GetSettingsFolder);

  lFilePath := GetSettingsFilePath;
  lTempPath := lFilePath + '.tmp';

  GC(lIni, TIniFile.Create(lTempPath), g);

  lIni.WriteString(cSectionScan, cKeyStartPath, fStartPath);
  lIni.WriteInteger(cSectionScan, cKeyMaxDepth, fMaxDepth);
  lIni.WriteInteger(cSectionScan, cKeyThrottleLimit, fThrottleLimit);
  lIni.WriteInteger(cSectionScan, cKeyCacheTtlSeconds, fCacheTtlSeconds);
  lIni.WriteString(cSectionScan, cKeyTargetRepoName, fTargetRepoName);
  lIni.WriteBool(cSectionDebug, cKeyDebugLogEnabled, fDebugLogEnabled);
  lIni.WriteString(cSectionDebug, cKeyDebugLogPath, fDebugLogPath);

  GC(lList, TStringList.Create, g);
  lList.StrictDelimiter := True;
  lList.Clear;
  for i := 0 to Length(fExcludeDirs) - 1 do
    lList.Add(fExcludeDirs[i]);
  lIni.WriteString(cSectionScan, cKeyExcludeDirs, lList.CommaText);

  lList.Clear;
  for i := 0 to Length(fRepoNameHistory) - 1 do
    lList.Add(fRepoNameHistory[i]);
  lIni.WriteString(cSectionHistory, cKeyRepoNameHistory, lList.CommaText);

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
