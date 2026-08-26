unit URepoListModel;

interface

uses
  System.Generics.Collections, System.Generics.Defaults, System.SysUtils,
  UModels;

{$SCOPEDENUMS ON}

type
  TRepoListFilter = (rlfAttention, rlfAll, rlfDirty, rlfBehind, rlfDetached, rlfClean);
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
    function MatchesFilter(const aItem: TRepoListItem; const aFilter: TRepoListFilter): Boolean;
    procedure RebuildVisible;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure AddWaiting(const aRepoRoot, aDisplayPath: string);
    procedure AddOrUpdate(const aStatus: TRepoStatus; const aDisplayPath: string);
    procedure SetFilter(const aFilter: TRepoListFilter);
    function Count: Integer;
    function VisibleCount: Integer;
    function ItemAtVisible(const aIndex: Integer): TRepoListItem;
    function FindVisibleIndex(const aRepoRoot: string): Integer;
    function FilterCount(const aFilter: TRepoListFilter): Integer;
  end;

implementation

constructor TRepoListModel.Create;
begin
  inherited Create;
  fItems := TList<TRepoListItem>.Create;
  fVisible := TList<Integer>.Create;
  fIndexByRoot := TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  fFilter := TRepoListFilter.rlfAttention;
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
begin
  if Trim(aRepoRoot) = '' then
    Exit;
  if fIndexByRoot.TryGetValue(aRepoRoot, lIndex) then
  begin
    lItem := fItems[lIndex];
    if (lItem.State = TRepoListItemState.rlisWaiting) and (aDisplayPath <> '') then
    begin
      lItem.DisplayPath := aDisplayPath;
      fItems[lIndex] := lItem;
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
    fVisible.Add(lIndex);
end;

procedure TRepoListModel.AddOrUpdate(const aStatus: TRepoStatus; const aDisplayPath: string);
var
  lIndex: Integer;
  lItem: TRepoListItem;
  lWasVisible: Boolean;
  lIsVisible: Boolean;
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
    fItems[lIndex] := lItem;
    lIsVisible := MatchesFilter(lItem, fFilter);
    if lWasVisible <> lIsVisible then
      RebuildVisible;
  end else begin
    lIndex := fItems.Add(lItem);
    fIndexByRoot.Add(aStatus.RepoRoot, lIndex);
    if MatchesFilter(lItem, fFilter) then
      fVisible.Add(lIndex);
  end;
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

function TRepoListModel.MatchesFilter(const aItem: TRepoListItem;
  const aFilter: TRepoListFilter): Boolean;
begin
  if aItem.State = TRepoListItemState.rlisWaiting then
    Exit(aFilter in [TRepoListFilter.rlfAttention, TRepoListFilter.rlfAll]);
  case aFilter of
    TRepoListFilter.rlfAttention:
      Result := aItem.Status.HasProblem;
    TRepoListFilter.rlfAll:
      Result := True;
    TRepoListFilter.rlfDirty:
      Result := aItem.Status.IsDirty;
    TRepoListFilter.rlfBehind:
      Result := aItem.Status.IsOutOfDate;
    TRepoListFilter.rlfDetached:
      Result := SameText(aItem.Status.Branch, '(detached)');
    TRepoListFilter.rlfClean:
      Result := not aItem.Status.HasProblem;
  else
    Result := True;
  end;
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
end;

end.
