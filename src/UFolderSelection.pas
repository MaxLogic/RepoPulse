unit UFolderSelection;

interface

uses
  System.IOUtils, System.SysUtils;

type
  TFolderSelectionState = (fssUnchecked, fssChecked, fssMixed);

  TFolderSelectionRule = record
    Path: string;
    Included: Boolean;
  end;

function NormalizeSelectionPath(const aPath: string): string;
function IsSameOrDescendantPath(const aPath, aAncestor: string): Boolean;
function EvaluateFolderSelection(const aPath: string;
  const aRules: TArray<TFolderSelectionRule>): Boolean;

function SetFolderSelection(const aPath: string; const aIncluded: Boolean;
  const aRules: TArray<TFolderSelectionRule>): TArray<TFolderSelectionRule>;
function GetFolderSelectionState(const aPath: string;
  const aRules: TArray<TFolderSelectionRule>): TFolderSelectionState;
function SelectedFolderRoots(const aRules: TArray<TFolderSelectionRule>): TArray<string>;

implementation

function NormalizeSelectionPath(const aPath: string): string;
var
  lRoot: string;
begin
  if Trim(aPath) = '' then
    Exit('');
  Result := TPath.GetFullPath(aPath.Replace('/', '\')).ToLowerInvariant;
  lRoot := TPath.GetPathRoot(Result);
  while (Length(Result) > Length(lRoot)) and (Result[Length(Result)] = '\') do
    Delete(Result, Length(Result), 1);
  if ExcludeTrailingPathDelimiter(Result) = ExcludeTrailingPathDelimiter(lRoot) then
    Result := IncludeTrailingPathDelimiter(lRoot);
end;

function MatchesNormalizedAncestor(const aPath, aAncestor: string): Boolean;
begin
  Result := (aPath <> '') and (aAncestor <> '') and
    ((aPath = aAncestor) or aPath.StartsWith(IncludeTrailingPathDelimiter(aAncestor)));
end;

function IsSameOrDescendantPath(const aPath, aAncestor: string): Boolean;
begin
  Result := MatchesNormalizedAncestor(NormalizeSelectionPath(aPath),
    NormalizeSelectionPath(aAncestor));
end;

function EvaluateFolderSelection(const aPath: string;
  const aRules: TArray<TFolderSelectionRule>): Boolean;
var
  lPath, lRulePath: string;
  lBestLength: Integer;
  lRule: TFolderSelectionRule;
begin
  Result := False;
  lPath := NormalizeSelectionPath(aPath);
  if lPath = '' then
    Exit;
  lBestLength := -1;
  for lRule in aRules do
  begin
    lRulePath := NormalizeSelectionPath(lRule.Path);
    if (Length(lRulePath) >= lBestLength) and MatchesNormalizedAncestor(lPath, lRulePath) then
    begin
      lBestLength := Length(lRulePath);
      Result := lRule.Included;
    end;
  end;
end;

function CanonicalRules(const aRules: TArray<TFolderSelectionRule>): TArray<TFolderSelectionRule>;
var
  i, j, lCount: Integer;
  lRule: TFolderSelectionRule;
  lInherited: Boolean;
begin
  SetLength(Result, Length(aRules));
  lCount := 0;
  for i := 0 to High(aRules) do
  begin
    lRule := aRules[i];
    lRule.Path := NormalizeSelectionPath(lRule.Path);
    if lRule.Path = '' then
      Continue;
    j := 0;
    while (j < lCount) and (Result[j].Path <> lRule.Path) do
      Inc(j);
    Result[j] := lRule;
    if j = lCount then
      Inc(lCount);
  end;
  SetLength(Result, lCount);
  // Parents precede descendants; lexical order also makes snapshots stable.
  for i := 1 to High(Result) do
  begin
    lRule := Result[i];
    j := i - 1;
    while (j >= 0) and (CompareStr(Result[j].Path, lRule.Path) > 0) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := lRule;
  end;
  lCount := 0;
  for i := 0 to High(Result) do
  begin
    lRule := Result[i];
    lInherited := False;
    for j := 0 to lCount - 1 do
      if MatchesNormalizedAncestor(lRule.Path, Result[j].Path) then
        lInherited := Result[j].Included;
    if lRule.Included <> lInherited then
    begin
      Result[lCount] := lRule;
      Inc(lCount);
    end;
  end;
  SetLength(Result, lCount);
end;

function SetFolderSelection(const aPath: string; const aIncluded: Boolean;
  const aRules: TArray<TFolderSelectionRule>): TArray<TFolderSelectionRule>;
var
  lPath: string;
  lRule: TFolderSelectionRule;
  lCount: Integer;
begin
  lPath := NormalizeSelectionPath(aPath);
  if lPath = '' then
    Exit(Copy(aRules));
  SetLength(Result, Length(aRules) + 1);
  lCount := 0;
  for lRule in aRules do
    if not IsSameOrDescendantPath(lRule.Path, lPath) then
    begin
      Result[lCount] := lRule;
      Inc(lCount);
    end;
  Result[lCount].Path := lPath;
  Result[lCount].Included := aIncluded;
  SetLength(Result, lCount + 1);
  Result := CanonicalRules(Result);
end;

function GetFolderSelectionState(const aPath: string;
  const aRules: TArray<TFolderSelectionRule>): TFolderSelectionState;
var
  lPath: string;
  lIncluded: Boolean;
  lRule: TFolderSelectionRule;
begin
  lPath := NormalizeSelectionPath(aPath);
  if lPath = '' then
    Exit(TFolderSelectionState.fssUnchecked);
  lIncluded := EvaluateFolderSelection(lPath, aRules);
  for lRule in aRules do
    if IsSameOrDescendantPath(lRule.Path, lPath) and
      (EvaluateFolderSelection(lRule.Path, aRules) <> lIncluded) then
      Exit(TFolderSelectionState.fssMixed);
  if lIncluded then
    Result := TFolderSelectionState.fssChecked
  else
    Result := TFolderSelectionState.fssUnchecked;
end;

function SelectedFolderRoots(const aRules: TArray<TFolderSelectionRule>): TArray<string>;
var
  lRules: TArray<TFolderSelectionRule>;
  lRule: TFolderSelectionRule;
  i, lCount: Integer;
  lCovered: Boolean;
begin
  lRules := CanonicalRules(aRules);
  SetLength(Result, Length(lRules));
  lCount := 0;
  for lRule in lRules do
    if lRule.Included then
    begin
      lCovered := False;
      for i := 0 to lCount - 1 do
        if MatchesNormalizedAncestor(lRule.Path, Result[i]) then
        begin
          lCovered := True;
          Break;
        end;
      if not lCovered then
      begin
        Result[lCount] := lRule.Path;
        Inc(lCount);
      end;
    end;
  SetLength(Result, lCount);
end;

end.
