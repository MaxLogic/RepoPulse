unit UScanPaths;

interface

uses
  System.Classes, System.SysUtils;

function TryNormalizeScanPaths(const aLines: TStrings; out aPaths: TArray<string>;
  out aError: string): Boolean;

implementation

resourcestring
  rsScanPathRequired = 'At least one scan path is required.';
  rsScanPathMissing = 'Scan path does not exist: %s';

function TryNormalizeScanPaths(const aLines: TStrings; out aPaths: TArray<string>;
  out aError: string): Boolean;
var
  lPaths: TStringList;
  lPath: string;
  i: Integer;
begin
  aPaths := [];
  aError := '';
  if aLines = nil then
  begin
    aError := rsScanPathRequired;
    Exit(False);
  end;

  lPaths := TStringList.Create;
  try
    lPaths.CaseSensitive := False;
    for i := 0 to aLines.Count - 1 do
    begin
      lPath := Trim(aLines[i]);
      if lPath = '' then
        Continue;
      if not DirectoryExists(lPath) then
      begin
        aError := Format(rsScanPathMissing, [lPath]);
        Exit(False);
      end;
      if lPaths.IndexOf(lPath) < 0 then
        lPaths.Add(lPath);
    end;

    if lPaths.Count = 0 then
    begin
      aError := rsScanPathRequired;
      Exit(False);
    end;

    SetLength(aPaths, lPaths.Count);
    for i := 0 to lPaths.Count - 1 do
      aPaths[i] := lPaths[i];
    Result := True;
  finally
    lPaths.Free;
  end;
end;

end.
