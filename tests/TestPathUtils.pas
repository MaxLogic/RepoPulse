unit TestPathUtils;

interface

uses
  DUnitX.TestFramework, UPathRules;

type
  [TestFixture]
  TPathUtilsTests = class
  public
    [Test]
    procedure NormalizePath_LowersAndTrims;
    [Test]
    procedure DepthFromRoot_CountsSegments;
  end;

implementation

procedure TPathUtilsTests.NormalizePath_LowersAndTrims;
var
  lPath: string;
  lNorm: string;
begin
  lPath := 'C:\Root\SomeDir\\';
  lNorm := NormalizePathForMatch(lPath);
  Assert.AreEqual('c:/root/somedir', lNorm);
end;

procedure TPathUtilsTests.DepthFromRoot_CountsSegments;
var
  lRoot: string;
  lPath: string;
  lDepth: Integer;
begin
  lRoot := 'C:\root';
  lPath := 'C:\root\a\b\c';
  lDepth := GetDepthFromRoot(lPath, lRoot);
  Assert.AreEqual(3, lDepth);
end;

initialization
  TDUnitX.RegisterTestFixture(TPathUtilsTests);

end.
