unit UBulkActionResults;

interface

uses
  System.Generics.Collections, System.SysUtils,
  AutoFree;

type
  TBulkActionFailure = record
    RepoRoot: string;
    ErrorText: string;
  end;

  TBulkActionResults = class
  private
    fFailures: TList<TBulkActionFailure>;
    class function IsFailureLine(const aLine: string): Boolean; static;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure AddFailure(const aRepoRoot, aErrorText: string);
    function Count: Integer;
    function BuildReport(const aActionName: string; const aTotal: Integer): string;
    class function SignificantLine(const aErrorText: string;
      const aMaxLength: Integer = 300): string; static;
  end;

implementation

constructor TBulkActionResults.Create;
begin
  inherited Create;
  fFailures := TList<TBulkActionFailure>.Create;
end;

destructor TBulkActionResults.Destroy;
begin
  fFailures.Free;
  inherited;
end;

procedure TBulkActionResults.Clear;
begin
  fFailures.Clear;
end;

procedure TBulkActionResults.AddFailure(const aRepoRoot, aErrorText: string);
var
  lFailure: TBulkActionFailure;
begin
  lFailure.RepoRoot := aRepoRoot;
  lFailure.ErrorText := aErrorText;
  fFailures.Add(lFailure);
end;

function TBulkActionResults.Count: Integer;
begin
  Result := fFailures.Count;
end;

function TBulkActionResults.BuildReport(const aActionName: string;
  const aTotal: Integer): string;
var
  g: TGarbos;
  i: Integer;
  lBuilder: TStringBuilder;
  lFailureWord: string;
begin
  if fFailures.Count = 1 then
    lFailureWord := 'failure'
  else
    lFailureWord := 'failures';
  GC(lBuilder, TStringBuilder.Create, g);
  lBuilder.AppendFormat('%s completed for %d repositories with %d %s.',
    [aActionName, aTotal, fFailures.Count, lFailureWord]);
  if fFailures.Count > 0 then
    lBuilder.Append(sLineBreak).Append(sLineBreak);
  for i := 0 to fFailures.Count - 1 do
  begin
    if i > 0 then
      lBuilder.Append(sLineBreak);
    lBuilder.Append(fFailures[i].RepoRoot).Append(': ').Append(
      SignificantLine(fFailures[i].ErrorText));
  end;
  Result := lBuilder.ToString;
end;

class function TBulkActionResults.SignificantLine(const aErrorText: string;
  const aMaxLength: Integer): string;
const
  cNoDiagnostic = 'No diagnostic was returned.';
var
  c: Char;
  lCandidateLine: string;
  lLine: string;
  lLines: TArray<string>;
  lNormalized: string;
  lWhitespace: Boolean;
begin
  lNormalized := aErrorText.Replace(#13#10, #10).Replace(#13, #10);
  lLines := lNormalized.Split([#10]);
  lLine := '';
  for lCandidateLine in lLines do
  begin
    if Trim(lCandidateLine) <> '' then
    begin
      if lLine = '' then
        lLine := Trim(lCandidateLine);
      if IsFailureLine(lCandidateLine) then
      begin
        lLine := Trim(lCandidateLine);
        Break;
      end;
    end;
  end;
  if lLine = '' then
    Exit(cNoDiagnostic);

  Result := '';
  lWhitespace := False;
  for c in lLine do
  begin
    if c <= ' ' then
      lWhitespace := True
    else begin
      if lWhitespace and (Result <> '') then
        Result := Result + ' ';
      Result := Result + c;
      lWhitespace := False;
      if Length(Result) > aMaxLength then
        Break;
    end;
  end;
  if (aMaxLength > 3) and (Length(Result) > aMaxLength) then
    Result := Copy(Result, 1, aMaxLength - 3) + '...'
  else if (aMaxLength >= 0) and (Length(Result) > aMaxLength) then
    SetLength(Result, aMaxLength);
end;

class function TBulkActionResults.IsFailureLine(const aLine: string): Boolean;
var
  lLine: string;
begin
  lLine := Trim(aLine).ToLowerInvariant;
  Result := lLine.StartsWith('fatal:') or lLine.StartsWith('error:') or
    lLine.StartsWith('you are not ') or lLine.StartsWith('conflict ') or
    lLine.StartsWith('conflict (') or lLine.StartsWith('cannot ') or
    lLine.StartsWith('unable to ') or lLine.StartsWith('aborting');
end;

end.
