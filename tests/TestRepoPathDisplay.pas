unit TestRepoPathDisplay;

interface

uses
  DUnitX.TestFramework, URepoPathDisplay;

type
  [TestFixture]
  TRepoPathDisplayTests = class
  public
    [Test]
    procedure BuildRelativeRepoPath_StripsScanRootPrefix;
    [Test]
    procedure BuildRelativeRepoPath_FallsBackToRepoNameOutsideScanRoot;
    [Test]
    procedure BuildRelativeRepoPath_UsesMostSpecificConfiguredRoot;
  end;

implementation

procedure TRepoPathDisplayTests.BuildRelativeRepoPath_StripsScanRootPrefix;
begin
  Assert.AreEqual('MaxLogic/SkillSearch',
    BuildRelativeRepoPath('F:/Projects/MaxLogic/SkillSearch', 'f:\projects\'));
end;

procedure TRepoPathDisplayTests.BuildRelativeRepoPath_FallsBackToRepoNameOutsideScanRoot;
begin
  Assert.AreEqual('SkillSearch',
    BuildRelativeRepoPath('F:\other\SkillSearch', 'F:\projects\'));
end;

procedure TRepoPathDisplayTests.BuildRelativeRepoPath_UsesMostSpecificConfiguredRoot;
begin
  Assert.AreEqual('RepoPulse', BuildRelativeRepoPath('F:\projects\MaxLogic\RepoPulse',
    ['F:\projects', 'F:\projects\MaxLogic']));
end;

initialization
  TDUnitX.RegisterTestFixture(TRepoPathDisplayTests);

end.
