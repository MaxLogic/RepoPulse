unit TestGitParsing;

interface

uses
  DUnitX.TestFramework, UGitClient;

type
  [TestFixture]
  TGitParsingTests = class
  public
    [Test]
    procedure ParseStatusPorcelain_StagedAndUnstaged;
    [Test]
    procedure ParseAheadBehind_Basic;
  end;

implementation

procedure TGitParsingTests.ParseStatusPorcelain_StagedAndUnstaged;
var
  lLines: TArray<string>;
  lParse: TGitStatusParse;
begin
  lLines := ['M  src/Unit1.pas', ' M src/Unit2.pas', '?? new.txt'];
  lParse := TGitClient.ParseStatusPorcelain(lLines);

  Assert.IsTrue(lParse.HasStaged, 'Expected staged changes');
  Assert.IsTrue(lParse.HasUnstaged, 'Expected unstaged changes');
  Assert.IsTrue(lParse.HasUntracked, 'Expected untracked changes');
  Assert.IsTrue(lParse.Summary.Contains('Unit1.pas'), 'Expected Unit1.pas in summary');
  Assert.IsTrue(lParse.Summary.Contains('Unit2.pas'), 'Expected Unit2.pas in summary');
  Assert.IsTrue(lParse.Summary.Contains('new.txt'), 'Expected new.txt in summary');
end;

procedure TGitParsingTests.ParseAheadBehind_Basic;
var
  lAhead: Integer;
  lBehind: Integer;
  lOk: Boolean;
begin
  lOk := TGitClient.ParseAheadBehind('3 5', lAhead, lBehind);
  Assert.IsTrue(lOk);
  Assert.AreEqual(3, lAhead);
  Assert.AreEqual(5, lBehind);

  lOk := TGitClient.ParseAheadBehind('10'#9'2', lAhead, lBehind);
  Assert.IsTrue(lOk);
  Assert.AreEqual(10, lAhead);
  Assert.AreEqual(2, lBehind);
end;

initialization
  TDUnitX.RegisterTestFixture(TGitParsingTests);

end.
