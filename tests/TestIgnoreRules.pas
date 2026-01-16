unit TestIgnoreRules;

interface

uses
  DUnitX.TestFramework, UPathRules;

type
  [TestFixture]
  TIgnoreRulesTests = class
  public
    [Test]
    procedure IgnoreBySegment;
    [Test]
    procedure IgnoreByRelativePattern;
    [Test]
    procedure IgnoreByAbsolutePattern;
  end;

implementation

procedure TIgnoreRulesTests.IgnoreBySegment;
var
  lRule: TIgnorePattern;
  lRoot: string;
  lDir: string;
begin
  lRoot := 'C:\root';
  lDir := 'C:\root\foo\node_modules';

  lRule := Default(TIgnorePattern);
  lRule.Pattern := 'node_modules';
  lRule.HasSlash := False;
  lRule.IsAbsolute := False;

  Assert.IsTrue(ShouldIgnoreDirectory(lDir, NormalizePathForMatch(lRoot), [lRule]));
end;

procedure TIgnoreRulesTests.IgnoreByRelativePattern;
var
  lRule: TIgnorePattern;
  lRoot: string;
  lDir: string;
begin
  lRoot := 'C:\root';
  lDir := 'C:\root\tools\alpha\bin';

  lRule := Default(TIgnorePattern);
  lRule.Pattern := 'tools/*/bin';
  lRule.HasSlash := True;
  lRule.IsAbsolute := False;

  Assert.IsTrue(ShouldIgnoreDirectory(lDir, NormalizePathForMatch(lRoot), [lRule]));
end;

procedure TIgnoreRulesTests.IgnoreByAbsolutePattern;
var
  lRule: TIgnorePattern;
  lRoot: string;
  lDir: string;
begin
  lRoot := 'C:\root';
  lDir := 'C:\root\secret\data';

  lRule := Default(TIgnorePattern);
  lRule.Pattern := 'c:/root/secret*';
  lRule.HasSlash := True;
  lRule.IsAbsolute := True;

  Assert.IsTrue(ShouldIgnoreDirectory(lDir, NormalizePathForMatch(lRoot), [lRule]));
end;

initialization
  TDUnitX.RegisterTestFixture(TIgnoreRulesTests);

end.
