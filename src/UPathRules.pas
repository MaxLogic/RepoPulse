unit UPathRules;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.Masks, System.SysUtils,

  AutoFree;

type
  TIgnorePattern = record
    Pattern: string;
    HasSlash: Boolean;
    IsAbsolute: Boolean;
    Raw: string;
  end;

function NormalizePathForMatch(const aFullPath: string): string;
function GetRelativeForMatch(const aFullNorm: string; const aRootNorm: string): string;
function GetDepthFromRoot(const aFullPath: string; const aRootPath: string): Integer;
function LoadIgnorePatterns(const aPath: string): TArray<TIgnorePattern>;
function ShouldIgnoreDirectory(const aDirFullPath: string; const aRootNorm: string;
  const aIgnorePatterns: TArray<TIgnorePattern>): Boolean;

implementation

function NormalizePathForMatch(const aFullPath: string): string;
begin
  Result := aFullPath.Replace('\', '/').TrimRight(['/']).ToLowerInvariant;
end;

function GetRelativeForMatch(const aFullNorm: string; const aRootNorm: string): string;
begin
  if aFullNorm.StartsWith(aRootNorm) then
    Result := aFullNorm.Substring(aRootNorm.Length).TrimLeft(['/'])
  else begin
    Result := aFullNorm;
  end;
end;

function GetDepthFromRoot(const aFullPath: string; const aRootPath: string): Integer;
var
  lFull: string;
  lRoot: string;
  lRel: string;
  lParts: TArray<string>;
begin
  lFull := NormalizePathForMatch(aFullPath);
  lRoot := NormalizePathForMatch(aRootPath);
  lRel := GetRelativeForMatch(lFull, lRoot);
  if lRel = '' then
    Exit(0);
  lParts := lRel.Split(['/'], TStringSplitOptions.ExcludeEmpty);
  Result := Length(lParts);
end;

function LoadIgnorePatterns(const aPath: string): TArray<TIgnorePattern>;
var
  lLines: TStringList;
  g: TGarbos;
  lList: TList<TIgnorePattern>;
  lLine: string;
  lTrimmed: string;
  lPattern: string;
  lItem: TIgnorePattern;
  i: Integer;
  lSlash: Integer;
  lIsAbs: Boolean;
begin
  Result := [];
  if not FileExists(aPath) then
    Exit;

  GC(lLines, TStringList.Create, g);
  lLines.LoadFromFile(aPath, TEncoding.UTF8);
  GC(lList, TList<TIgnorePattern>.Create, g);

  for i := 0 to lLines.Count - 1 do
  begin
    lLine := lLines[i];
    lSlash := lLine.IndexOf('#');
    if lSlash >= 0 then
      lLine := lLine.Substring(0, lSlash);
    lTrimmed := lLine.Trim;
    if lTrimmed = '' then
      Continue;

    lPattern := lTrimmed.Replace('\', '/').TrimRight(['/']);
    if lPattern = '' then
      Continue;

    lIsAbs := False;
    if Length(lPattern) >= 3 then
    begin
      if (lPattern[2] = ':') and (lPattern[3] = '/') then
        lIsAbs := True;
    end;
    if lPattern.StartsWith('//') then
      lIsAbs := True;

    lItem := Default(TIgnorePattern);
    lItem.Pattern := lPattern.ToLowerInvariant;
    lItem.HasSlash := lPattern.Contains('/');
    lItem.IsAbsolute := lIsAbs;
    lItem.Raw := lTrimmed;
    lList.Add(lItem);
  end;

  Result := lList.ToArray;
end;

function ShouldIgnoreDirectory(const aDirFullPath: string; const aRootNorm: string;
  const aIgnorePatterns: TArray<TIgnorePattern>): Boolean;
var
  lFull: string;
  lRel: string;
  lRule: TIgnorePattern;
  lSegs: TArray<string>;
  lSeg: string;
begin
  Result := False;
  if Length(aIgnorePatterns) = 0 then
    Exit(False);

  lFull := NormalizePathForMatch(aDirFullPath);
  lRel := GetRelativeForMatch(lFull, aRootNorm);

  for lRule in aIgnorePatterns do
  begin
    if lRule.IsAbsolute then
    begin
      if MatchesMask(lFull, lRule.Pattern) then
        Exit(True);
      Continue;
    end;

    if lRule.HasSlash then
    begin
      if MatchesMask(lRel, lRule.Pattern) then
        Exit(True);
    end else begin
      lSegs := lRel.Split(['/'], TStringSplitOptions.ExcludeEmpty);
      for lSeg in lSegs do
      begin
        if MatchesMask(lSeg, lRule.Pattern) then
          Exit(True);
      end;
    end;
  end;
end;

end.
