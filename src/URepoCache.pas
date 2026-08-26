unit URepoCache;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.JSON, System.SysUtils,

  Winapi.Windows,

  AutoFree, maxLogic.StrUtils,
  UModels;

type
  TRepoCache = class
  private
    fEntries: TDictionary<string, TRepoCacheEntry>;
    fInventory: TArray<string>;
    fInventoryFingerprint: string;
  public
    constructor Create;
    destructor Destroy; override;
    function TryGet(const aKey: string; out aEntry: TRepoCacheEntry): Boolean;
    procedure ApplyUpdate(const aUpdate: TRepoCacheUpdate);
    procedure SetInventory(const aFingerprint: string; const aRepoRoots: TArray<string>);
    function GetValidInventory(const aFingerprint: string): TArray<string>;
    function LoadFromFile(const aFilePath: string; out aError: string): Boolean;
    function SaveToFile(const aFilePath: string; const aTtlSeconds: Integer; out aError: string): Boolean;
    class function BuildScanFingerprint(const aScanPaths: TArray<string>; const aFilterPattern: string;
      const aMaxDepth: Integer; const aIgnoreContent: string): string; static;
    class function IsValidRepositoryRoot(const aRepoRoot: string): Boolean; static;
    property Entries: TDictionary<string, TRepoCacheEntry> read fEntries;
  end;

implementation

constructor TRepoCache.Create;
begin
  inherited Create;
  fEntries := TDictionary<string, TRepoCacheEntry>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
end;

destructor TRepoCache.Destroy;
begin
  fEntries.Free;
  inherited;
end;

procedure TRepoCache.ApplyUpdate(const aUpdate: TRepoCacheUpdate);
var
  lEntry: TRepoCacheEntry;
begin
  if aUpdate.Key = '' then
    Exit;

  if not fEntries.TryGetValue(aUpdate.Key, lEntry) then
    lEntry := Default(TRepoCacheEntry);

  if aUpdate.OriginUrl <> '' then
    lEntry.OriginUrl := aUpdate.OriginUrl;
  if aUpdate.LastFetchUtc <> '' then
    lEntry.LastFetchUtc := aUpdate.LastFetchUtc;
  if aUpdate.HasLastFetchOk then
    lEntry.LastFetchOk := aUpdate.LastFetchOk;
  if aUpdate.LastFetchError <> '' then
    lEntry.LastFetchError := aUpdate.LastFetchError;

  fEntries.AddOrSetValue(aUpdate.Key, lEntry);
end;

function TRepoCache.TryGet(const aKey: string; out aEntry: TRepoCacheEntry): Boolean;
begin
  Result := fEntries.TryGetValue(aKey, aEntry);
end;

class function TRepoCache.BuildScanFingerprint(const aScanPaths: TArray<string>;
  const aFilterPattern: string; const aMaxDepth: Integer; const aIgnoreContent: string): string;
var
  g: TGarbos;
  lPaths: TStringList;
  lPath: string;
  lNormalized: string;
  lIgnore: string;
begin
  GC(lPaths, TStringList.Create, g);
  lPaths.CaseSensitive := False;
  lPaths.Duplicates := dupIgnore;
  lPaths.Sorted := True;
  for lPath in aScanPaths do
  begin
    lNormalized := Trim(lPath).Replace('/', '\').TrimRight(['\']).ToLowerInvariant;
    if lNormalized <> '' then
      lPaths.Add(lNormalized);
  end;

  lIgnore := aIgnoreContent.Replace(#13#10, #10).Replace(#13, #10).Trim;
  lNormalized := Trim(aFilterPattern).ToLowerInvariant;
  if lNormalized = '' then
    lNormalized := '*';
  Result := Format('v1|depth=%d|filter=%d:%s|ignore=%d:%s|paths=%d',
    [aMaxDepth, Length(lNormalized), lNormalized, Length(lIgnore), lIgnore, lPaths.Count]);
  for lPath in lPaths do
    Result := Result + Format('|%d:%s', [Length(lPath), lPath]);
end;

function TRepoCache.GetValidInventory(const aFingerprint: string): TArray<string>;
var
  g: TGarbos;
  lValid: TList<string>;
  lRepoRoot: string;
begin
  Result := [];
  if (aFingerprint = '') or (aFingerprint <> fInventoryFingerprint) then
    Exit;
  GC(lValid, TList<string>.Create, g);
  for lRepoRoot in fInventory do
  begin
    if IsValidRepositoryRoot(lRepoRoot) then
      lValid.Add(lRepoRoot);
  end;
  Result := lValid.ToArray;
end;

class function TRepoCache.IsValidRepositoryRoot(const aRepoRoot: string): Boolean;
begin
  Result := DirectoryExists(aRepoRoot) and
    (DirectoryExists(TPath.Combine(aRepoRoot, '.git')) or FileExists(TPath.Combine(aRepoRoot, '.git')));
end;

procedure TRepoCache.SetInventory(const aFingerprint: string; const aRepoRoots: TArray<string>);
var
  g: TGarbos;
  lRoots: TList<string>;
  lSeen: TDictionary<string, Boolean>;
  lRepoRoot: string;
begin
  GC(lRoots, TList<string>.Create, g);
  GC(lSeen, TDictionary<string, Boolean>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase), g);
  for lRepoRoot in aRepoRoots do
  begin
    if (Trim(lRepoRoot) <> '') and not lSeen.ContainsKey(lRepoRoot) then
    begin
      lSeen.Add(lRepoRoot, True);
      lRoots.Add(lRepoRoot);
    end;
  end;
  fInventoryFingerprint := aFingerprint;
  fInventory := lRoots.ToArray;
end;

function TRepoCache.LoadFromFile(const aFilePath: string; out aError: string): Boolean;
var
  g: TGarbos;
  lJson: string;
  lRoot: TJSONObject;
  lRepos: TJSONObject;
  lPair: TJSONPair;
  lObj: TJSONObject;
  lEntry: TRepoCacheEntry;
  lValue: TJSONValue;
  lInventory: TJSONArray;
  lVersion: Integer;
  i: Integer;
begin
  aError := '';
  Result := True;
  fEntries.Clear;
  fInventory := [];
  fInventoryFingerprint := '';

  if not FileExists(aFilePath) then
    Exit(True);

  try
    lJson := TFile.ReadAllText(aFilePath, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      aError := E.Message;
      Exit(False);
    end;
  end;

  if lJson.Trim = '' then
    Exit(True);

  lValue := TJSONObject.ParseJSONValue(lJson);
  if lValue = nil then
  begin
    aError := 'cache JSON parse failed';
    Exit(False);
  end;

  GC(lValue, g);

  if not (lValue is TJSONObject) then
  begin
    aError := 'cache JSON root is not an object';
    Exit(False);
  end;

  lRoot := TJSONObject(lValue);
  lVersion := lRoot.GetValue<Integer>('version', 1);
  if lVersion >= 2 then
  begin
    fInventoryFingerprint := lRoot.GetValue<string>('scanFingerprint', '');
    if lRoot.Values['inventory'] is TJSONArray then
    begin
      lInventory := TJSONArray(lRoot.Values['inventory']);
      SetLength(fInventory, lInventory.Count);
      for i := 0 to lInventory.Count - 1 do
        fInventory[i] := lInventory.Items[i].Value;
    end;
  end;

  lRepos := nil;
  if lRoot.Values['repos'] is TJSONObject then
    lRepos := TJSONObject(lRoot.Values['repos']);
  if lRepos = nil then
    Exit(True);

  for lPair in lRepos do
  begin
    if not (lPair.JsonValue is TJSONObject) then
      Continue;
    lObj := TJSONObject(lPair.JsonValue);
    lEntry := Default(TRepoCacheEntry);
    lEntry.OriginUrl := lObj.GetValue<string>('originUrl', '');
    lEntry.LastFetchUtc := lObj.GetValue<string>('lastFetchUtc', '');
    lEntry.LastFetchError := lObj.GetValue<string>('lastFetchError', '');
    lEntry.LastFetchOk := lObj.GetValue<Boolean>('lastFetchOk', False);
    fEntries.AddOrSetValue(lPair.JsonString.Value, lEntry);
  end;
end;

function TRepoCache.SaveToFile(const aFilePath: string; const aTtlSeconds: Integer; out aError: string): Boolean;
var
  g: TGarbos;
  lRoot: TJSONObject;
  lRepos: TJSONObject;
  lEntry: TRepoCacheEntry;
  lKey: string;
  lObj: TJSONObject;
  lTempPath: string;
  lJson: string;
  lInventory: TJSONArray;
  lRepoRoot: string;
begin
  aError := '';
  Result := False;

  GC(lRoot, TJSONObject.Create, g);
  lRepos := TJSONObject.Create;
  lRoot.AddPair('version', TJSONNumber.Create(2));
  lRoot.AddPair('ttlSeconds', TJSONNumber.Create(aTtlSeconds));
  lRoot.AddPair('scanFingerprint', fInventoryFingerprint);
  lInventory := TJSONArray.Create;
  for lRepoRoot in fInventory do
    lInventory.AddElement(TJSONString.Create(lRepoRoot));
  lRoot.AddPair('inventory', lInventory);
  lRoot.AddPair('repos', lRepos);

  for lKey in fEntries.Keys do
  begin
    lEntry := fEntries[lKey];
    lObj := TJSONObject.Create;
    lObj.AddPair('originUrl', lEntry.OriginUrl);
    lObj.AddPair('lastFetchUtc', lEntry.LastFetchUtc);
    lObj.AddPair('lastFetchOk', TJSONBool.Create(lEntry.LastFetchOk));
    lObj.AddPair('lastFetchError', lEntry.LastFetchError);
    lRepos.AddPair(lKey, lObj);
  end;

  lJson := lRoot.ToJSON;
  lTempPath := aFilePath + '.tmp';

  try
    TFile.WriteAllText(lTempPath, lJson, TEncoding.UTF8);
    if not MoveFileEx(PChar(lTempPath), PChar(aFilePath), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  except
    on E: Exception do
    begin
      aError := E.Message;
      Exit(False);
    end;
  end;

  Result := True;
end;

end.
