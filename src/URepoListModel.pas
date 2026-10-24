unit URepoListModel;

interface

uses
  System.Generics.Collections, System.Generics.Defaults, System.SysUtils,
  MaxLogic.StrUtils,
  UFolderSelection, UModels;

{$SCOPEDENUMS ON}

type
  TRepoListFilter = (rlfAttention, rlfOperationFailed, rlfScanFailed, rlfUnrelatedHistory,
    rlfReadyToPull, rlfBehindOnly, rlfDiverged, rlfAhead, rlfDirty, rlfDetached, rlfNoIssues, rlfAll);
  TRepoListAction = (rlaPull, rlaPush);
  TRepoListItemState = (rlisWaiting, rlisReady);

  TRepoListItem = record
    RepoRoot: string;
    DisplayPath: string;
    State: TRepoListItemState;
    Status: TRepoStatus;
  end;

  TRepoListModel = class
  private
    fItems: TList<TRepoListItem>;
    fVisible: TList<Integer>;
    fIndexByRoot: TDictionary<string, Integer>;
    fFilter: TRepoListFilter;
    fSearch: TFilterEx;
    fExclusions: TArray<string>;
    fPathRules: TArray<TFolderSelectionRule>;
    fHasPathSelection: Boolean;
    function IsExcluded(const aRoot: string; const aPatterns: TArray<string>): Boolean;
    function CompareItemIndices(const aLeft, aRight: Integer): Integer;
    function HasAttentionProblem(const aStatus: TRepoStatus): Boolean;
    procedure InsertVisibleSorted(const aItemIndex: Integer);
    function MatchesAction(const aItem: TRepoListItem; const aAction: TRepoListAction): Boolean;
    function MatchesFilter(const aItem: TRepoListItem; const aFilter: TRepoListFilter): Boolean;
    procedure RebuildVisible;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure ReconcileInventory(const aCommittedRoots: TArray<string>);
    procedure AddWaiting(const aRepoRoot, aDisplayPath: string);
    procedure AddOrUpdate(const aStatus: TRepoStatus; const aDisplayPath: string);
    procedure SetFilter(const aFilter: TRepoListFilter);
    procedure SetSearchQuery(const aQuery: string);
    procedure SetExclusions(const aPatterns: TArray<string>);
    procedure SetPathSelection(const aRules: TArray<TFolderSelectionRule>);
    function PreviewExcludedRoots(const aPatterns: TArray<string>): TArray<string>;
    function Count: Integer;
    function VisibleCount: Integer;
    function ItemAtVisible(const aIndex: Integer): TRepoListItem;
    function FindVisibleIndex(const aRepoRoot: string): Integer;
    function FilterCount(const aFilter: TRepoListFilter): Integer;
    function HasVisibleAction(const aAction: TRepoListAction): Boolean;
    function VisibleRoots: TArray<string>;
    function VisibleActionRoots(const aAction: TRepoListAction): TArray<string>;
  end;

implementation

uses
  AutoFree;

procedure TRepoListModel.ReconcileInventory(const aCommittedRoots: TArray<string>);
var
  g: TGarbos;
  lCommitted: THashSet<string>;
  lRoot: string;
  lItem: TRepoListItem;
  i, lRetainedCount: Integer;
begin
  // The caller supplies complete committed membership, not just this run's discoveries.
  GC(lCommitted, THashSet<string>.Create(fIndexByRoot.Comparer), g);
  for lRoot in aCommittedRoots do
    if Trim(lRoot) <> '' then
      lCommitted.Add(lRoot);

  lRetainedCount := 0;
  for i := 0 to fItems.Count - 1 do
    if lCommitted.Contains(fItems[i].RepoRoot) then
    begin
      fItems[lRetainedCount] := fItems[i];
      Inc(lRetainedCount);
    end;
  fItems.Count := lRetainedCount;
  fIndexByRoot.Clear;
  for i := 0 to fItems.Count - 1 do
    fIndexByRoot.Add(fItems[i].RepoRoot, i);

  for lRoot in aCommittedRoots do
    if (Trim(lRoot) <> '') and not fIndexByRoot.ContainsKey(lRoot) then
    begin
      lItem := Default(TRepoListItem);
      lItem.RepoRoot := lRoot;
      lItem.DisplayPath := lRoot;
      lItem.State := TRepoListItemState.rlisWaiting;
      fIndexByRoot.Add(lRoot, fItems.Add(lItem));
    end;
  RebuildVisible;
end;

function TRepoListModel.VisibleRoots: TArray<string>;
var
  i: Integer;
begin
  SetLength(Result, fVisible.Count);
  for i := 0 to fVisible.Count - 1 do
    Result[i] := fItems[fVisible[i]].RepoRoot;
end;

procedure TRepoListModel.SetPathSelection(const aRules: TArray<TFolderSelectionRule>);
begin
  fPathRules := Copy(aRules);
  fHasPathSelection := True;
  RebuildVisible;
end;

function MatchesRepositoryGlob(const aText, aPattern: string): Boolean;
var
  i, j: Integer;
  lStar, lRetry: Integer;
begin
  i := 1;
  j := 1;
  lStar := 0;
  lRetry := 0;
  while i <= Length(aText) do
  begin
    if (j <= Length(aPattern)) and ((aPattern[j] = '?') or (aPattern[j] = aText[i])) then
    begin
      Inc(i);
      Inc(j);
    end else if (j <= Length(aPattern)) and (aPattern[j] = '*') then
    begin
      lStar := j;
      lRetry := i;
      Inc(j);
    end else if lStar <> 0 then
    begin
      Inc(lRetry);
      i := lRetry;
      j := lStar + 1;
    end else
      Exit(False);
  end;
  while (j <= Length(aPattern)) and (aPattern[j] = '*') do
    Inc(j);
  Result := j > Length(aPattern);
end;

function TRepoListModel.IsExcluded(const aRoot: string;
  const aPatterns: TArray<string>): Boolean;
var
  lFull, lName, lPattern, lRaw: string;
begin
  lFull := aRoot.Replace('/', '\').TrimRight(['\']).ToLowerInvariant;
  lName := ExtractFileName(lFull);
  for lRaw in aPatterns do
  begin
    if Trim(lRaw) = '' then
      Continue;
    lPattern := lRaw.Replace('/', '\').ToLowerInvariant;
    if MatchesRepositoryGlob(lName, lPattern) or
      MatchesRepositoryGlob(lFull, lPattern) or MatchesRepositoryGlob(lFull + '\', lPattern) then
      Exit(True);
  end;
  Result := False;
end;

procedure TRepoListModel.SetSearchQuery(const aQuery: string);
begin
  fSearch := TFilterEx.Create(Trim(aQuery));
  RebuildVisible;
end;

procedure TRepoListModel.SetExclusions(const aPatterns: TArray<string>);
begin
  fExclusions := Copy(aPatterns);
  RebuildVisible;
end;

function TRepoListModel.PreviewExcludedRoots(const aPatterns: TArray<string>): TArray<string>;
var
  lItem: TRepoListItem;
  lRoots: TList<string>;
begin
  lRoots := TList<string>.Create;
  try
    for lItem in fItems do
      if IsExcluded(lItem.RepoRoot, aPatterns) then
        lRoots.Add(lItem.RepoRoot);
    Result := lRoots.ToArray;
  finally
    lRoots.Free;
  end;
end;

constructor TRepoListModel.Create;
begin
  inherited Create;
  fItems := TList<TRepoListItem>.Create;
  fVisible := TList<Integer>.Create;
  fIndexByRoot := TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  fFilter := TRepoListFilter.rlfAttention;
  fSearch := TFilterEx.Create('');
end;

destructor TRepoListModel.Destroy;
begin
  fIndexByRoot.Free;
  fVisible.Free;
  fItems.Free;
  inherited;
end;

procedure TRepoListModel.Clear;
begin
  fItems.Clear;
  fVisible.Clear;
  fIndexByRoot.Clear;
end;

procedure TRepoListModel.AddWaiting(const aRepoRoot, aDisplayPath: string);
var
  lIndex: Integer;
  lItem: TRepoListItem;
  lPreviousPath: string;
begin
  if Trim(aRepoRoot) = '' then
    Exit;
  if fIndexByRoot.TryGetValue(aRepoRoot, lIndex) then
  begin
    lItem := fItems[lIndex];
    if (lItem.State = TRepoListItemState.rlisWaiting) and (aDisplayPath <> '') then
    begin
      lPreviousPath := lItem.DisplayPath;
      lItem.DisplayPath := aDisplayPath;
      fItems[lIndex] := lItem;
      if not SameText(lPreviousPath, aDisplayPath) and MatchesFilter(lItem, fFilter) then
        RebuildVisible;
    end;
    Exit;
  end;

  lItem := Default(TRepoListItem);
  lItem.RepoRoot := aRepoRoot;
  lItem.DisplayPath := aDisplayPath;
  lItem.State := TRepoListItemState.rlisWaiting;
  lIndex := fItems.Add(lItem);
  fIndexByRoot.Add(aRepoRoot, lIndex);
  if MatchesFilter(lItem, fFilter) then
    InsertVisibleSorted(lIndex);
end;

procedure TRepoListModel.AddOrUpdate(const aStatus: TRepoStatus; const aDisplayPath: string);
var
  lIndex: Integer;
  lItem: TRepoListItem;
  lWasVisible: Boolean;
  lIsVisible: Boolean;
  lPreviousPath: string;
begin
  if Trim(aStatus.RepoRoot) = '' then
    Exit;

  lItem := Default(TRepoListItem);
  lItem.RepoRoot := aStatus.RepoRoot;
  lItem.DisplayPath := aDisplayPath;
  lItem.State := TRepoListItemState.rlisReady;
  lItem.Status := aStatus;
  if fIndexByRoot.TryGetValue(aStatus.RepoRoot, lIndex) then
  begin
    lWasVisible := MatchesFilter(fItems[lIndex], fFilter);
    lPreviousPath := fItems[lIndex].DisplayPath;
    fItems[lIndex] := lItem;
    lIsVisible := MatchesFilter(lItem, fFilter);
    if (lWasVisible <> lIsVisible) or
       (lIsVisible and not SameText(lPreviousPath, aDisplayPath)) then
      RebuildVisible;
  end else begin
    lIndex := fItems.Add(lItem);
    fIndexByRoot.Add(aStatus.RepoRoot, lIndex);
    if MatchesFilter(lItem, fFilter) then
      InsertVisibleSorted(lIndex);
  end;
end;

function TRepoListModel.CompareItemIndices(const aLeft, aRight: Integer): Integer;
begin
  Result := CompareText(fItems[aLeft].DisplayPath, fItems[aRight].DisplayPath);
  if Result = 0 then
    Result := CompareText(fItems[aLeft].RepoRoot, fItems[aRight].RepoRoot);
end;

procedure TRepoListModel.InsertVisibleSorted(const aItemIndex: Integer);
var
  lHigh: Integer;
  lLow: Integer;
  lMiddle: Integer;
begin
  lLow := 0;
  lHigh := fVisible.Count;
  while lLow < lHigh do
  begin
    lMiddle := lLow + ((lHigh - lLow) div 2);
    if CompareItemIndices(fVisible[lMiddle], aItemIndex) < 0 then
      lLow := lMiddle + 1
    else
      lHigh := lMiddle;
  end;
  fVisible.Insert(lLow, aItemIndex);
end;

procedure TRepoListModel.SetFilter(const aFilter: TRepoListFilter);
begin
  if fFilter = aFilter then
    Exit;
  fFilter := aFilter;
  RebuildVisible;
end;

function TRepoListModel.Count: Integer;
begin
  Result := fItems.Count;
end;

function TRepoListModel.VisibleCount: Integer;
begin
  Result := fVisible.Count;
end;

function TRepoListModel.ItemAtVisible(const aIndex: Integer): TRepoListItem;
begin
  if (aIndex < 0) or (aIndex >= fVisible.Count) then
    raise EArgumentOutOfRangeException.CreateFmt('Visible repository index %d is out of range.', [aIndex]);
  Result := fItems[fVisible[aIndex]];
end;

function TRepoListModel.FindVisibleIndex(const aRepoRoot: string): Integer;
var
  lItemIndex: Integer;
  i: Integer;
begin
  Result := -1;
  if not fIndexByRoot.TryGetValue(aRepoRoot, lItemIndex) then
    Exit;
  for i := 0 to fVisible.Count - 1 do
  begin
    if fVisible[i] = lItemIndex then
      Exit(i);
  end;
end;

function TRepoListModel.FilterCount(const aFilter: TRepoListFilter): Integer;
var
  lItem: TRepoListItem;
begin
  Result := 0;
  for lItem in fItems do
  begin
    if MatchesFilter(lItem, aFilter) then
      Inc(Result);
  end;
end;

function TRepoListModel.VisibleActionRoots(const aAction: TRepoListAction): TArray<string>;
var
  i: Integer;
  lItem: TRepoListItem;
  lRoots: TList<string>;
begin
  lRoots := TList<string>.Create;
  try
    for i := 0 to fVisible.Count - 1 do
    begin
      lItem := fItems[fVisible[i]];
      if MatchesAction(lItem, aAction) then
        lRoots.Add(lItem.RepoRoot);
    end;
    Result := lRoots.ToArray;
  finally
    lRoots.Free;
  end;
end;

function TRepoListModel.HasVisibleAction(const aAction: TRepoListAction): Boolean;
var
  i: Integer;
begin
  for i := 0 to fVisible.Count - 1 do
  begin
    if MatchesAction(fItems[fVisible[i]], aAction) then
      Exit(True);
  end;
  Result := False;
end;

function TRepoListModel.MatchesAction(const aItem: TRepoListItem;
  const aAction: TRepoListAction): Boolean;
begin
  if (aItem.State <> TRepoListItemState.rlisReady) or aItem.Status.IsCached or
    aItem.Status.ScanFailed then
    Exit(False);
  case aAction of
    TRepoListAction.rlaPull:
      Result := aItem.Status.IsOutOfDate and (not aItem.Status.UnrelatedHistory);
    TRepoListAction.rlaPush:
      Result := aItem.Status.IsDirty;
  else
    Result := False;
  end;
end;

function TRepoListModel.MatchesFilter(const aItem: TRepoListItem;
  const aFilter: TRepoListFilter): Boolean;
begin
  if fHasPathSelection and not EvaluateFolderSelection(aItem.RepoRoot, fPathRules) then
    Exit(False);
  if IsExcluded(aItem.RepoRoot, fExclusions) or
    not (fSearch.Matches(ExtractFileName(aItem.RepoRoot.Replace('/', '\'))) or
      fSearch.Matches(aItem.RepoRoot)) then
    Exit(False);
  if aItem.State = TRepoListItemState.rlisWaiting then
    Exit(aFilter in [TRepoListFilter.rlfAttention, TRepoListFilter.rlfAll]);
  case aFilter of
    TRepoListFilter.rlfAttention:
      Result := HasAttentionProblem(aItem.Status);
    TRepoListFilter.rlfOperationFailed:
      Result := (Trim(aItem.Status.LastPullError) <> '') or
        (Trim(aItem.Status.LastPushError) <> '');
    TRepoListFilter.rlfScanFailed:
      Result := aItem.Status.ScanFailed;
    TRepoListFilter.rlfUnrelatedHistory:
      Result := aItem.Status.UnrelatedHistory;
    TRepoListFilter.rlfReadyToPull:
      Result := (aItem.Status.Behind > 0) and (aItem.Status.Ahead = 0) and
        (not aItem.Status.IsDirty) and (not aItem.Status.UnrelatedHistory);
    TRepoListFilter.rlfBehindOnly:
      Result := (aItem.Status.Behind > 0) and (aItem.Status.Ahead = 0) and
        (not aItem.Status.UnrelatedHistory);
    TRepoListFilter.rlfDiverged:
      Result := (aItem.Status.Behind > 0) and (aItem.Status.Ahead > 0) and
        (not aItem.Status.UnrelatedHistory);
    TRepoListFilter.rlfAhead:
      Result := (aItem.Status.Ahead > 0) and (aItem.Status.Behind = 0) and
        (not aItem.Status.UnrelatedHistory);
    TRepoListFilter.rlfDirty:
      Result := aItem.Status.IsDirty;
    TRepoListFilter.rlfDetached:
      Result := SameText(aItem.Status.Branch, '(detached)');
    TRepoListFilter.rlfNoIssues:
      Result := not HasAttentionProblem(aItem.Status);
    TRepoListFilter.rlfAll:
      Result := True;
  else
    Result := True;
  end;
end;

function TRepoListModel.HasAttentionProblem(const aStatus: TRepoStatus): Boolean;
begin
  Result := aStatus.HasProblem or aStatus.ScanFailed or aStatus.UnrelatedHistory or
    (Trim(aStatus.LastPullError) <> '') or (Trim(aStatus.LastPushError) <> '');
end;

procedure TRepoListModel.RebuildVisible;
var
  i: Integer;
begin
  fVisible.Clear;
  for i := 0 to fItems.Count - 1 do
  begin
    if MatchesFilter(fItems[i], fFilter) then
      fVisible.Add(i);
  end;
  fVisible.Sort(TComparer<Integer>.Construct(CompareItemIndices));
end;

end.
