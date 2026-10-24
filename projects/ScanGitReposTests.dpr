program ScanGitReposTests;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  FastMM5 in 'F:\projects\3rdParty\FastMM5\FastMM5\FastMM5.pas',
  System.IOUtils, System.SysUtils,

  DUnitX.Loggers.Console, DUnitX.Loggers.XML.NUnit, DUnitX.TestFramework,
  TestAppSettings in '..\tests\TestAppSettings.pas',
  TestBoundedParallel in '..\tests\TestBoundedParallel.pas',
  TestBulkActionResults in '..\tests\TestBulkActionResults.pas',
  TestGitParsing in '..\tests\TestGitParsing.pas',
  TestFolderSelection in '..\tests\TestFolderSelection.pas',
  TestFolderTreeFrame in '..\tests\TestFolderTreeFrame.pas',
  TestIgnoreRules in '..\tests\TestIgnoreRules.pas',
  TestPathUtils in '..\tests\TestPathUtils.pas',
  TestRepoDiscovery in '..\tests\TestRepoDiscovery.pas',
  TestRepoAccessibility in '..\tests\TestRepoAccessibility.pas',
  TestRepoCache in '..\tests\TestRepoCache.pas',
  TestRepoListModel in '..\tests\TestRepoListModel.pas',
  TestRepositoryExclusionsDialog in '..\tests\TestRepositoryExclusionsDialog.pas',
  TestRepoPathDisplay in '..\tests\TestRepoPathDisplay.pas',
  TestScanPaths in '..\tests\TestScanPaths.pas',
  TestTortoiseGit in '..\tests\TestTortoiseGit.pas',
  TestUiEventQueue in '..\tests\TestUiEventQueue.pas',
  TestUiForms in '..\tests\TestUiForms.pas',
  UTortoiseGit in '..\src\UTortoiseGit.pas';

var
  lRunner: ITestRunner;
  lResults: IRunResults;
  lLogger: ITestLogger;
  lXmlLogger: ITestLogger;
  lResultsPath: string;
  lResultsDir: string;

begin
  // T-052: retain full leak diagnostics without a modal shutdown dialog.
  ReportMemoryLeaksOnShutdown := False;
  FastMM_MessageBoxEvents := [];
  FastMM_LogToFileEvents := FastMM_LogToFileEvents +
    [mmetUnexpectedMemoryLeakDetail, mmetUnexpectedMemoryLeakSummary];
  FastMM_SetEventLogFilename(PWideChar(TPath.Combine(GetCurrentDir, 'FastMM5-errors.log')));
  try
    if FastMM_GetInstallationState <> mmisInstalled then
      raise Exception.Create('FastMM5 is not the installed test memory manager');
    Writeln('FastMM5 installed: ', CFastMM_Version);
    lRunner := TDUnitX.CreateRunner;
    lRunner.UseRTTI := True;

    lLogger := TDUnitXConsoleLogger.Create(True);
    lRunner.AddLogger(lLogger);

    lResultsPath := TPath.Combine(GetCurrentDir, 'TestResults.xml');
    lResultsDir := ExtractFilePath(lResultsPath);
    if (lResultsDir <> '') and (not DirectoryExists(lResultsDir)) then
    begin
      if not ForceDirectories(lResultsDir) then
        raise EInOutError.CreateFmt('Unable to create test results directory: %s (cwd=%s)', [lResultsDir, GetCurrentDir]);
    end;

    try
      lXmlLogger := TDUnitXXMLNUnitFileLogger.Create(lResultsPath);
    except
      on E: Exception do
        raise Exception.CreateFmt('Failed to create XML test logger. Path="%s". Cwd="%s". %s: %s',
          [lResultsPath, GetCurrentDir, E.ClassName, E.Message]);
    end;
    lRunner.AddLogger(lXmlLogger);

    lResults := lRunner.Execute;
    if not lResults.AllPassed then
      ExitCode := 1
    else
      ExitCode := 0;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
