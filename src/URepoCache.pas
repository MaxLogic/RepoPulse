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
  public
    constructor Create;
    destructor Destroy; override;
    function TryGet(const aKey: string; out aEntry: TRepoCacheEntry): Boolean;
    procedure ApplyUpdate(const aUpdate: TRepoCacheUpdate);
    function LoadFromFile(const aFilePath: string; out aError: string): Boolean;
    function SaveToFile(const aFilePath: string; const aTtlSeconds: Integer; out aError: string): Boolean;
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
begin
  aError := '';
  Result := True;
  fEntries.Clear;

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
begin
  aError := '';
  Result := False;

  GC(lRoot, TJSONObject.Create, g);
  lRepos := TJSONObject.Create;
  lRoot.AddPair('version', TJSONNumber.Create(1));
  lRoot.AddPair('ttlSeconds', TJSONNumber.Create(aTtlSeconds));
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
