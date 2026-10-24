unit TestScanPaths;

interface

uses
  System.Classes, System.IOUtils, System.SysUtils,

  AutoFree, DUnitX.TestFramework,
  UScanPaths, UScanPathsDialog;

type
  [TestFixture]
  TScanPathsTests = class
  public
    [Test]
    procedure TryNormalizeScanPaths_TrimsAndDeduplicatesExistingDirectories;
    [Test]
    procedure TryNormalizeScanPaths_RejectsMissingDirectory;
    [Test]
    procedure IgnoreRules_LoadsFileAndFallsBackToDefaults;
    [Test]
    procedure IgnoreRules_SavesUtf8FileAndCreatesParentFolder;
  end;

implementation

procedure TScanPathsTests.IgnoreRules_LoadsFileAndFallsBackToDefaults;
var
  g: TGarbos;
  lLines: TStringList;
  lTempRoot: string;
  lPath: string;
  lError: string;
begin
  lTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseIgnoreLoad-' + TPath.GetRandomFileName);
  lPath := TPath.Combine(lTempRoot, '.ignoredirectory');
  ForceDirectories(lTempRoot);
  try
    TFile.WriteAllText(lPath, 'node_modules' + sLineBreak + 'src/generated', TEncoding.UTF8);
    GC(lLines, TStringList.Create, g);

    Assert.IsTrue(TryLoadIgnoreRules(lPath, ['.git', 'bin'], lLines, lError), lError);
    Assert.AreEqual(2, lLines.Count);
    Assert.AreEqual('node_modules', lLines[0]);
    Assert.AreEqual('src/generated', lLines[1]);

    Assert.IsTrue(TryLoadIgnoreRules(TPath.Combine(lTempRoot, 'missing'), ['.git', 'bin'],
      lLines, lError), lError);
    Assert.AreEqual(2, lLines.Count);
    Assert.AreEqual('.git', lLines[0]);
    Assert.AreEqual('bin', lLines[1]);
  finally
    g.Clear;
    if DirectoryExists(lTempRoot) then
      TDirectory.Delete(lTempRoot, True);
  end;
end;

procedure TScanPathsTests.IgnoreRules_SavesUtf8FileAndCreatesParentFolder;
var
  g: TGarbos;
  lLines: TStringList;
  lLoaded: TStringList;
  lTempRoot: string;
  lPath: string;
  lError: string;
begin
  lTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseIgnoreSave-' + TPath.GetRandomFileName);
  lPath := TPath.Combine(TPath.Combine(lTempRoot, 'settings'), '.ignoredirectory');
  try
    GC(lLines, TStringList.Create, g);
    GC(lLoaded, TStringList.Create, g);
    lLines.Add('.git');
    lLines.Add('build/*');

    Assert.IsTrue(TrySaveIgnoreRules(lPath, lLines, lError), lError);
    Assert.IsTrue(FileExists(lPath));
    lLoaded.LoadFromFile(lPath, TEncoding.UTF8);
    Assert.AreEqual(lLines.Text, lLoaded.Text);
  finally
    g.Clear;
    if DirectoryExists(lTempRoot) then
      TDirectory.Delete(lTempRoot, True);
  end;
end;

procedure TScanPathsTests.TryNormalizeScanPaths_TrimsAndDeduplicatesExistingDirectories;
var
  g: TGarbos;
  lLines: TStringList;
  lTempRoot: string;
  lFirstPath: string;
  lSecondPath: string;
  lPaths: TArray<string>;
  lError: string;
begin
  lTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseScanPaths-' + TPath.GetRandomFileName);
  lFirstPath := TPath.Combine(lTempRoot, 'First');
  lSecondPath := TPath.Combine(lTempRoot, 'Second');
  ForceDirectories(lFirstPath);
  ForceDirectories(lSecondPath);
  try
    GC(lLines, TStringList.Create, g);
    lLines.Add('  ' + lFirstPath + '  ');
    lLines.Add('');
    lLines.Add(UpperCase(lFirstPath));
    lLines.Add(lSecondPath);

    Assert.IsTrue(TryNormalizeScanPaths(lLines, lPaths, lError), lError);
    Assert.AreEqual(2, Length(lPaths));
    Assert.AreEqual(lFirstPath, lPaths[0]);
    Assert.AreEqual(lSecondPath, lPaths[1]);
  finally
    g.Clear;
    if DirectoryExists(lTempRoot) then
      TDirectory.Delete(lTempRoot, True);
  end;
end;

procedure TScanPathsTests.TryNormalizeScanPaths_RejectsMissingDirectory;
var
  g: TGarbos;
  lLines: TStringList;
  lMissingPath: string;
  lPaths: TArray<string>;
  lError: string;
begin
  lMissingPath := TPath.Combine(TPath.GetTempPath, 'RepoPulseMissing-' + TPath.GetRandomFileName);
  GC(lLines, TStringList.Create, g);
  lLines.Add(lMissingPath);

  Assert.IsFalse(TryNormalizeScanPaths(lLines, lPaths, lError));
  Assert.IsTrue(lError.Contains(lMissingPath), lError);
end;

initialization
  TDUnitX.RegisterTestFixture(TScanPathsTests);

end.
