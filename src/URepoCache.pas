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
    fSnapshots: TDictionary<string, TRepoStatus>;
    fInventory: TArray<string>;
    fInventoryFingerprint: string;
    fLoadFailed: Boolean;
    fLoadedPath: string;
    fLoadError: string;
    fRevision: Int64;
    fDirty: Boolean;
    fSavedRevision: Int64;
    fSavedPath: string;
    fSavedTtl: Integer;
    function TryLoadFromFile(const aFilePath: string; out aError: string): Boolean;
    class function ReadStatus(const aRoot: string; const aJson: TJSONObject): TRepoStatus; static;
    class function WriteStatus(const aStatus: TRepoStatus): TJSONObject; static;
  public
    constructor Create;
    destructor Destroy; override;
    function TryGet(const aKey: string; out aEntry: TRepoCacheEntry): Boolean;
    procedure ApplyUpdate(const aUpdate: TRepoCacheUpdate);
    procedure StoreStatus(const aStatus: TRepoStatus; const aObservedUtc: string);
    function TryGetStatus(const aRepoRoot: string; out aStatus: TRepoStatus): Boolean;
    function GetInventory: TArray<string>;
    procedure SetInventory(const aFingerprint: string; const aRepoRoots: TArray<string>);
    function TryCommitDiscoveredInventory(const aRepoRoots: TArray<string>;
      const aFilePath: string; const aTtlSeconds: Integer; out aError: string): Boolean;
    function GetValidInventory(const aFingerprint: string): TArray<string>;
    function LoadFromFile(const aFilePath: string; out aError: string): Boolean;
    function EnsureLoaded(const aFilePath: string; out aError: string): Boolean;
    function FlushPending(const aFilePath: string; const aTtlSeconds: Integer; out aError: string): Boolean;
    function SaveToFile(const aFilePath: string; const aTtlSeconds: Integer; out aError: string): Boolean;
    class function BuildScanFingerprint(const aScanPaths: TArray<string>; const aFilterPattern: string;
      const aMaxDepth: Integer; const aIgnoreContent: string): string; static;
    class function IsValidRepositoryRoot(const aRepoRoot: string): Boolean; static;
  end;

implementation

function TRepoCache.TryCommitDiscoveredInventory(const aRepoRoots: TArray<string>;
  const aFilePath: string; const aTtlSeconds: Integer; out aError: string): Boolean;
var
  lPrevious: TArray<string>;
  lFingerprint: string;
  lRevision: Int64;
  lDirty: Boolean;
begin
  Result := False;
  TMonitor.Enter(Self);
  try
    lPrevious := fInventory;
    lFingerprint := fInventoryFingerprint;
    lRevision := fRevision;
    lDirty := fDirty;
    try
      SetInventory('', lPrevious + aRepoRoots);
      Result := SaveToFile(aFilePath, aTtlSeconds, aError);
    finally
      if not Result then
      begin
        fInventory := lPrevious;
        fInventoryFingerprint := lFingerprint;
        fRevision := lRevision;
        fDirty := lDirty;
      end;
    end;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TRepoCache.EnsureLoaded(const aFilePath: string; out aError: string): Boolean;
var
  lPath: string;
begin
  lPath := ExpandFileName(aFilePath);
  TMonitor.Enter(Self);
  try
    if SameFileName(fLoadedPath, lPath) then
    begin
      aError := fLoadError;
      Exit(not fLoadFailed);
    end;
    Result := LoadFromFile(lPath, aError);
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TRepoCache.StoreStatus(const aStatus: TRepoStatus; const aObservedUtc: string);
var
  lStatus: TRepoStatus;
begin
  TMonitor.Enter(Self);
  try
    if aStatus.RepoRoot = '' then
      Exit;
    if aStatus.ScanFailed then
    begin
      if not fSnapshots.TryGetValue(aStatus.RepoRoot, lStatus) then
      begin
        lStatus := Default(TRepoStatus);
        lStatus.RepoRoot := aStatus.RepoRoot;
      end;
      lStatus.ScanFailed := True;
      lStatus.ScanError := aStatus.ScanError;
      lStatus.HasProblem := True;
    end else begin
      lStatus := aStatus;
      lStatus.LastAnalyzedUtc := aObservedUtc;
      lStatus.IsCached := False;
    end;
    lStatus.LastPullError := '';
    lStatus.LastPushError := '';
    lStatus.CacheUpdate := Default(TRepoCacheUpdate);
    lStatus.MatchedFolders := Copy(lStatus.MatchedFolders);
    fSnapshots.AddOrSetValue(aStatus.RepoRoot, lStatus);
    Inc(fRevision);
    fDirty := True;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TRepoCache.TryGetStatus(const aRepoRoot: string; out aStatus: TRepoStatus): Boolean;
begin
  TMonitor.Enter(Self);
  try
    Result := fSnapshots.TryGetValue(aRepoRoot, aStatus);
    if Result then
      aStatus.MatchedFolders := Copy(aStatus.MatchedFolders);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TRepoCache.GetInventory: TArray<string>;
begin
  TMonitor.Enter(Self);
  try
    Result := Copy(fInventory);
  finally
    TMonitor.Exit(Self);
  end;
end;

class function TRepoCache.WriteStatus(const aStatus: TRepoStatus): TJSONObject;
var
  lFolders: TJSONArray;
  lFolder: string;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('lastAnalyzedUtc', aStatus.LastAnalyzedUtc);
    Result.AddPair('branch', aStatus.Branch);
    Result.AddPair('isSubmodule', TJSONBool.Create(aStatus.IsSubmodule));
    Result.AddPair('superprojectRoot', aStatus.SuperprojectRoot);
    Result.AddPair('submoduleMainRemoteRef', aStatus.SubmoduleMainRemoteRef);
    Result.AddPair('submoduleNeedsMainFastForward', TJSONBool.Create(aStatus.SubmoduleNeedsMainFastForward));
    Result.AddPair('hasOrigin', TJSONBool.Create(aStatus.HasOrigin));
    Result.AddPair('upstream', aStatus.Upstream);
    Result.AddPair('canCompare', TJSONBool.Create(aStatus.CanCompare));
    Result.AddPair('unrelatedHistory', TJSONBool.Create(aStatus.UnrelatedHistory));
    Result.AddPair('behind', TJSONNumber.Create(aStatus.Behind));
    Result.AddPair('ahead', TJSONNumber.Create(aStatus.Ahead));
    Result.AddPair('isOutOfDate', TJSONBool.Create(aStatus.IsOutOfDate));
    Result.AddPair('hasUnpushed', TJSONBool.Create(aStatus.HasUnpushed));
    Result.AddPair('isDirty', TJSONBool.Create(aStatus.IsDirty));
    Result.AddPair('dirtySummary', aStatus.DirtySummary);
    Result.AddPair('fetchFailed', TJSONBool.Create(aStatus.FetchFailed));
    Result.AddPair('fetchError', aStatus.FetchError);
    Result.AddPair('scanFailed', TJSONBool.Create(aStatus.ScanFailed));
    Result.AddPair('scanError', aStatus.ScanError);
    Result.AddPair('hasProblem', TJSONBool.Create(aStatus.HasProblem));
    Result.AddPair('gitDirPath', aStatus.GitDirPath);
    Result.AddPair('gitDirWritable', TJSONBool.Create(aStatus.GitDirWritable));
    Result.AddPair('gitDirReadOnly', TJSONBool.Create(aStatus.GitDirReadOnly));
    Result.AddPair('gitDirError', aStatus.GitDirError);
    Result.AddPair('modulesDirPath', aStatus.ModulesDirPath);
    Result.AddPair('modulesDirWritable', TJSONBool.Create(aStatus.ModulesDirWritable));
    Result.AddPair('modulesDirReadOnly', TJSONBool.Create(aStatus.ModulesDirReadOnly));
    Result.AddPair('modulesDirError', aStatus.ModulesDirError);
    lFolders := TJSONArray.Create;
    Result.AddPair('matchedFolders', lFolders);
    for lFolder in aStatus.MatchedFolders do
      lFolders.Add(lFolder);
  except
    Result.Free;
    raise;
  end;
end;

class function TRepoCache.ReadStatus(const aRoot: string; const aJson: TJSONObject): TRepoStatus;
var
  lFolders: TJSONArray;
  i: Integer;
begin
  Result := Default(TRepoStatus);
  Result.RepoRoot := aRoot;
  Result.IsCached := True;
  Result.LastAnalyzedUtc := aJson.GetValue<string>('lastAnalyzedUtc', '');
  Result.Branch := aJson.GetValue<string>('branch', '');
  Result.IsSubmodule := aJson.GetValue<Boolean>('isSubmodule', False);
  Result.SuperprojectRoot := aJson.GetValue<string>('superprojectRoot', '');
  Result.SubmoduleMainRemoteRef := aJson.GetValue<string>('submoduleMainRemoteRef', '');
  Result.SubmoduleNeedsMainFastForward := aJson.GetValue<Boolean>('submoduleNeedsMainFastForward', False);
  Result.HasOrigin := aJson.GetValue<Boolean>('hasOrigin', False);
  Result.Upstream := aJson.GetValue<string>('upstream', '');
  Result.CanCompare := aJson.GetValue<Boolean>('canCompare', False);
  Result.UnrelatedHistory := aJson.GetValue<Boolean>('unrelatedHistory', False);
  Result.Behind := aJson.GetValue<Integer>('behind', 0);
  Result.Ahead := aJson.GetValue<Integer>('ahead', 0);
  Result.IsOutOfDate := aJson.GetValue<Boolean>('isOutOfDate', False);
  Result.HasUnpushed := aJson.GetValue<Boolean>('hasUnpushed', False);
  Result.IsDirty := aJson.GetValue<Boolean>('isDirty', False);
  Result.DirtySummary := aJson.GetValue<string>('dirtySummary', '');
  Result.FetchFailed := aJson.GetValue<Boolean>('fetchFailed', False);
  Result.FetchError := aJson.GetValue<string>('fetchError', '');
  Result.ScanFailed := aJson.GetValue<Boolean>('scanFailed', False);
  Result.ScanError := aJson.GetValue<string>('scanError', '');
  Result.HasProblem := aJson.GetValue<Boolean>('hasProblem', False);
  Result.GitDirPath := aJson.GetValue<string>('gitDirPath', '');
  Result.GitDirWritable := aJson.GetValue<Boolean>('gitDirWritable', False);
  Result.GitDirReadOnly := aJson.GetValue<Boolean>('gitDirReadOnly', False);
  Result.GitDirError := aJson.GetValue<string>('gitDirError', '');
  Result.ModulesDirPath := aJson.GetValue<string>('modulesDirPath', '');
  Result.ModulesDirWritable := aJson.GetValue<Boolean>('modulesDirWritable', False);
  Result.ModulesDirReadOnly := aJson.GetValue<Boolean>('modulesDirReadOnly', False);
  Result.ModulesDirError := aJson.GetValue<string>('modulesDirError', '');
  if aJson.Values['matchedFolders'] is TJSONArray then
  begin
    lFolders := TJSONArray(aJson.Values['matchedFolders']);
    SetLength(Result.MatchedFolders, lFolders.Count);
    for i := 0 to lFolders.Count - 1 do
      Result.MatchedFolders[i] := lFolders.Items[i].Value;
  end;
end;

constructor TRepoCache.Create;
begin
  inherited Create;
  fEntries := TDictionary<string, TRepoCacheEntry>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fSnapshots := TDictionary<string, TRepoStatus>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
end;

destructor TRepoCache.Destroy;
begin
  fSnapshots.Free;
  fEntries.Free;
  inherited;
end;

procedure TRepoCache.ApplyUpdate(const aUpdate: TRepoCacheUpdate);
var
  lEntry: TRepoCacheEntry;
begin
  TMonitor.Enter(Self);
  try
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
    Inc(fRevision);
    fDirty := True;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TRepoCache.TryGet(const aKey: string; out aEntry: TRepoCacheEntry): Boolean;
begin
  TMonitor.Enter(Self);
  try
    Result := fEntries.TryGetValue(aKey, aEntry);
  finally
    TMonitor.Exit(Self);
  end;
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
  TMonitor.Enter(Self);
  try
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
  finally
    TMonitor.Exit(Self);
  end;
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
  TMonitor.Enter(Self);
  try
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
    Inc(fRevision);
    fDirty := True;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TRepoCache.LoadFromFile(const aFilePath: string; out aError: string): Boolean;
begin
  TMonitor.Enter(Self);
  try
    try
      Result := TryLoadFromFile(aFilePath, aError);
    except
      on E: Exception do
      begin
        aError := E.Message;
        Result := False;
      end;
    end;
    fLoadFailed := not Result;
    fLoadError := aError;
    fLoadedPath := ExpandFileName(aFilePath);
    Inc(fRevision);
    fDirty := False;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TRepoCache.TryLoadFromFile(const aFilePath: string; out aError: string): Boolean;
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
  lFolderValue: TJSONValue;
  i: Integer;
begin
  aError := '';
  Result := True;
  fEntries.Clear;
  fSnapshots.Clear;
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
  begin
    aError := 'cache file is empty';
    Exit(False);
  end;

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
  if not (lRoot.Values['version'] is TJSONNumber) then
  begin
    aError := 'cache version is missing or is not a number';
    Exit(False);
  end;
  lVersion := lRoot.GetValue<Integer>('version', 1);
  if not (lVersion in [1, 2, 3]) then
  begin
    aError := Format('Unsupported cache version: %d', [lVersion]);
    Exit(False);
  end;
  if not (lRoot.Values['repos'] is TJSONObject) then
  begin
    aError := 'cache repositories must be an object';
    Exit(False);
  end;
  if (lVersion >= 2) and not (lRoot.Values['inventory'] is TJSONArray) then
  begin
    aError := 'cache inventory must be an array';
    Exit(False);
  end;
  if (lVersion = 3) and not (lRoot.Values['snapshots'] is TJSONObject) then
  begin
    aError := 'cache snapshots must be an object';
    Exit(False);
  end;
  if lVersion >= 2 then
  begin
    fInventoryFingerprint := lRoot.GetValue<string>('scanFingerprint', '');
    if lRoot.Values['inventory'] is TJSONArray then
    begin
      lInventory := TJSONArray(lRoot.Values['inventory']);
      SetLength(fInventory, lInventory.Count);
      for i := 0 to lInventory.Count - 1 do
      begin
        if lInventory.Items[i].ClassType <> TJSONString then
        begin
          aError := 'cache inventory root must be a string';
          Exit(False);
        end;
        fInventory[i] := lInventory.Items[i].Value;
      end;
    end;
  end;

  if lRoot.Values['snapshots'] is TJSONObject then
  begin
    for lPair in TJSONObject(lRoot.Values['snapshots']) do
    begin
      if not (lPair.JsonValue is TJSONObject) then
      begin
        aError := 'cache snapshot is not an object';
        Exit(False);
      end;
      lObj := TJSONObject(lPair.JsonValue);
      if lObj.Values['matchedFolders'] <> nil then
      begin
        if not (lObj.Values['matchedFolders'] is TJSONArray) then
        begin
          aError := 'cache snapshot matched folders must be an array';
          Exit(False);
        end;
        for lFolderValue in TJSONArray(lObj.Values['matchedFolders']) do
        begin
          if lFolderValue.ClassType <> TJSONString then
          begin
            aError := 'cache snapshot matched folder must be a string';
            Exit(False);
          end;
        end;
      end;
      fSnapshots.AddOrSetValue(lPair.JsonString.Value,
        ReadStatus(lPair.JsonString.Value, lObj));
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
    begin
      aError := 'cache fetch entry must be an object';
      Exit(False);
    end;
    lObj := TJSONObject(lPair.JsonValue);
    lEntry := Default(TRepoCacheEntry);
    lEntry.OriginUrl := lObj.GetValue<string>('originUrl', '');
    lEntry.LastFetchUtc := lObj.GetValue<string>('lastFetchUtc', '');
    lEntry.LastFetchError := lObj.GetValue<string>('lastFetchError', '');
    lEntry.LastFetchOk := lObj.GetValue<Boolean>('lastFetchOk', False);
    fEntries.AddOrSetValue(lPair.JsonString.Value, lEntry);
  end;
end;

function TRepoCache.FlushPending(const aFilePath: string; const aTtlSeconds: Integer;
  out aError: string): Boolean;
begin
  TMonitor.Enter(Self);
  try
    aError := '';
    if not fDirty then
      Exit(True);
    Result := SaveToFile(aFilePath, aTtlSeconds, aError);
  finally
    TMonitor.Exit(Self);
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
  lSnapshots: TJSONObject;
begin
  TMonitor.Enter(Self);
  try
    aError := '';
    Result := False;

    if fLoadFailed then
    begin
      aError := 'Cache save refused because loading failed; preserve the original cache before rebuilding';
      Exit;
    end;
    if (fSavedRevision = fRevision) and (fSavedTtl = aTtlSeconds) and
      SameFileName(fSavedPath, ExpandFileName(aFilePath)) and FileExists(aFilePath) then
      Exit(True);

    GC(lRoot, TJSONObject.Create, g);
    lRepos := TJSONObject.Create;
    lRoot.AddPair('version', TJSONNumber.Create(3));
    lRoot.AddPair('ttlSeconds', TJSONNumber.Create(aTtlSeconds));
    lRoot.AddPair('scanFingerprint', fInventoryFingerprint);
    lInventory := TJSONArray.Create;
    for lRepoRoot in fInventory do
      lInventory.AddElement(TJSONString.Create(lRepoRoot));
    lRoot.AddPair('inventory', lInventory);
    lRoot.AddPair('repos', lRepos);
    lSnapshots := TJSONObject.Create;
    lRoot.AddPair('snapshots', lSnapshots);
    for lRepoRoot in fSnapshots.Keys do
      lSnapshots.AddPair(lRepoRoot, WriteStatus(fSnapshots[lRepoRoot]));

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
    lTempPath := aFilePath + '.' + TPath.GetRandomFileName + '.tmp';

    try
      TFile.WriteAllText(lTempPath, lJson, TEncoding.UTF8);
      if not MoveFileEx(PChar(lTempPath), PChar(aFilePath), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
        RaiseLastOSError;
    except
      on E: Exception do
      begin
        aError := E.Message;
        if FileExists(lTempPath) and not Winapi.Windows.DeleteFile(PChar(lTempPath)) then
          aError := aError + '; temporary cache cleanup failed: ' + SysErrorMessage(GetLastError);
        Exit(False);
      end;
    end;

    fDirty := False;
    fSavedRevision := fRevision;
    fSavedPath := ExpandFileName(aFilePath);
    fSavedTtl := aTtlSeconds;
    Result := True;
  finally
    TMonitor.Exit(Self);
  end;
end;

end.
