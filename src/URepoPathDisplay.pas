unit URepoPathDisplay;

interface

function BuildRelativeRepoPath(const aRepoRoot: string; const aStartPath: string): string; overload;
function BuildRelativeRepoPath(const aRepoRoot: string; const aStartPaths: TArray<string>): string; overload;

implementation

uses
  System.SysUtils;

function NormalizeDisplayPath(const aPath: string): string;
begin
  Result := aPath.Replace('\', '/').TrimRight(['/']);
end;

function BuildRelativeRepoPath(const aRepoRoot: string; const aStartPath: string): string;
var
  lBase: string;
  lBaseNorm: string;
  lRepoPath: string;
  lRepoNorm: string;
begin
  lRepoPath := NormalizeDisplayPath(aRepoRoot);
  lBase := NormalizeDisplayPath(Trim(aStartPath));
  if lBase <> '' then
  begin
    lBaseNorm := AnsiLowerCase(lBase);
    lRepoNorm := AnsiLowerCase(lRepoPath);
    if lRepoNorm.StartsWith(lBaseNorm) then
    begin
      if Length(lRepoPath) = Length(lBase) then
        Result := ''
      else
      begin
        if lRepoPath[Length(lBase) + 1] <> '/' then
          lBaseNorm := '';
        if lBaseNorm <> '' then
          Result := lRepoPath.Substring(Length(lBase)).TrimLeft(['/']);
      end;
      if Result <> '' then
        Exit;
    end;
  end;

  Result := ExtractFileName(ExcludeTrailingPathDelimiter(aRepoRoot));
  if Result = '' then
    Result := NormalizeDisplayPath(aRepoRoot);
end;

function BuildRelativeRepoPath(const aRepoRoot: string; const aStartPaths: TArray<string>): string;
var
  lStartPath: string;
  lBase: string;
  lBaseNorm: string;
  lBestBase: string;
  lRepoNorm: string;
begin
  lRepoNorm := AnsiLowerCase(NormalizeDisplayPath(aRepoRoot));
  lBestBase := '';
  for lStartPath in aStartPaths do
  begin
    lBase := NormalizeDisplayPath(Trim(lStartPath));
    lBaseNorm := AnsiLowerCase(lBase);
    if (lBaseNorm <> '') and ((lRepoNorm = lBaseNorm) or lRepoNorm.StartsWith(lBaseNorm + '/')) and
      (Length(lBase) > Length(lBestBase)) then
      lBestBase := lBase;
  end;
  Result := BuildRelativeRepoPath(aRepoRoot, lBestBase);
end;

end.
