unit TestBulkActionResults;

interface

uses
  System.SysUtils,
  AutoFree, DUnitX.TestFramework,
  UBulkActionResults;

type
  [TestFixture]
  TBulkActionResultsTests = class
  public
    [Test]
    procedure SignificantLine_UsesFirstNonEmptyLineAndCollapsesWhitespace;
    [Test]
    procedure SignificantLine_BoundsPathologicalSingleLine;
    [Test]
    procedure SignificantLine_UsesFallbackForEmptyDiagnostic;
    [Test]
    procedure SignificantLine_PrefersFailureOverProgressOutput;
    [Test]
    procedure BuildReport_UsesOneLogicalLinePerFailedRepository;
    [Test]
    procedure Clear_RemovesPreviousFailures;
  end;

implementation

procedure TBulkActionResultsTests.SignificantLine_UsesFirstNonEmptyLineAndCollapsesWhitespace;
begin
  Assert.AreEqual('fatal: cannot pull', TBulkActionResults.SignificantLine(
    sLineBreak + '  fatal:   cannot'#9'pull  ' + sLineBreak + 'secondary detail'));
end;

procedure TBulkActionResultsTests.SignificantLine_BoundsPathologicalSingleLine;
var
  lLine: string;
begin
  lLine := TBulkActionResults.SignificantLine(StringOfChar('x', 400));

  Assert.AreEqual(300, Length(lLine));
  Assert.IsTrue(lLine.EndsWith('...'));
end;

procedure TBulkActionResultsTests.SignificantLine_UsesFallbackForEmptyDiagnostic;
begin
  Assert.AreEqual('No diagnostic was returned.',
    TBulkActionResults.SignificantLine(sLineBreak + #9 + '  '));
end;

procedure TBulkActionResultsTests.SignificantLine_PrefersFailureOverProgressOutput;
begin
  Assert.AreEqual('You are not currently on a branch.',
    TBulkActionResults.SignificantLine('Fetching submodule lib/jedi' + sLineBreak +
      'You are not currently on a branch.' + sLineBreak +
      'Please specify which branch you want to merge with.'));
end;

procedure TBulkActionResultsTests.BuildReport_UsesOneLogicalLinePerFailedRepository;
var
  g: TGarbos;
  lResults: TBulkActionResults;
begin
  GC(lResults, TBulkActionResults.Create, g);
  lResults.AddFailure('C:\Repo A', 'fatal: first' + sLineBreak + 'secondary A');
  lResults.AddFailure('C:\Repo B', sLineBreak + 'denied' + sLineBreak + 'secondary B');

  Assert.AreEqual('Pull completed for 4 repositories with 2 failures.' +
    sLineBreak + sLineBreak + 'C:\Repo A: fatal: first' + sLineBreak +
    'C:\Repo B: denied', lResults.BuildReport('Pull', 4));
end;

procedure TBulkActionResultsTests.Clear_RemovesPreviousFailures;
var
  g: TGarbos;
  lResults: TBulkActionResults;
begin
  GC(lResults, TBulkActionResults.Create, g);
  lResults.AddFailure('C:\Repo', 'failed');
  lResults.Clear;

  Assert.AreEqual(0, lResults.Count);
end;

initialization
  TDUnitX.RegisterTestFixture(TBulkActionResultsTests);

end.
