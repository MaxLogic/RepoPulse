unit TestScanPaths;

interface

uses
  System.Classes, System.IOUtils, System.SysUtils,

  AutoFree, DUnitX.TestFramework,
  UScanPaths;

type
  [TestFixture]
  TScanPathsTests = class
  public
    [Test]
    procedure TryNormalizeScanPaths_TrimsAndDeduplicatesExistingDirectories;
    [Test]
    procedure TryNormalizeScanPaths_RejectsMissingDirectory;
  end;

implementation

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
