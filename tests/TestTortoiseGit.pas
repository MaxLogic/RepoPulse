unit TestTortoiseGit;

interface

uses
  System.IOUtils, System.SysUtils,

  DUnitX.TestFramework,
  UTortoiseGit;

type
  [TestFixture]
  TTortoiseGitTests = class
  public
    [Test]
    procedure BuildParameters_QuotesRepositoryPath;
    [Test]
    procedure ResolveExecutable_InstallDirectoryAndPath;
    [Test]
    procedure ResolveExecutable_MissingReturnsEmpty;
  end;

implementation

procedure TTortoiseGitTests.BuildParameters_QuotesRepositoryPath;
begin
  Assert.AreEqual('/command:commit /path:"F:\Work Tree\Repo"',
    TTortoiseGit.BuildParameters(TTortoiseGitCommand.tgcCommit, 'F:\Work Tree\Repo'));
  Assert.AreEqual('/command:sync /path:"F:\Work Tree\Repo"',
    TTortoiseGit.BuildParameters(TTortoiseGitCommand.tgcSync, 'F:\Work Tree\Repo'));
end;

procedure TTortoiseGitTests.ResolveExecutable_InstallDirectoryAndPath;
var
  lTempRoot: string;
  lInstallRoot: string;
  lInstallExe: string;
  lPathRoot: string;
  lPathExe: string;
begin
  lTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseTests-' + TPath.GetRandomFileName);
  lInstallRoot := TPath.Combine(lTempRoot, 'installed');
  lInstallExe := TPath.Combine(lInstallRoot, 'bin\TortoiseGitProc.exe');
  lPathRoot := TPath.Combine(lTempRoot, 'path');
  lPathExe := TPath.Combine(lPathRoot, 'TortoiseGitProc.exe');
  ForceDirectories(ExtractFilePath(lInstallExe));
  ForceDirectories(lPathRoot);
  try
    TFile.WriteAllBytes(lInstallExe, []);
    TFile.WriteAllBytes(lPathExe, []);

    Assert.AreEqual(lInstallExe,
      TTortoiseGit.ResolveExecutable(['Z:\missing\TortoiseGitProc.exe', lInstallRoot], ''));
    Assert.AreEqual(lInstallExe, TTortoiseGit.ResolveExecutable(['"' + lInstallExe + '"'], ''));
    Assert.AreEqual(lPathExe, TTortoiseGit.ResolveExecutable([], lPathRoot));
  finally
    if DirectoryExists(lTempRoot) then
      TDirectory.Delete(lTempRoot, True);
  end;
end;

procedure TTortoiseGitTests.ResolveExecutable_MissingReturnsEmpty;
begin
  Assert.AreEqual('', TTortoiseGit.ResolveExecutable(['Z:\missing\TortoiseGitProc.exe'],
    'Z:\also-missing'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTortoiseGitTests);

end.
