program ScanGitReposTests;

{$APPTYPE CONSOLE}

uses
  System.IOUtils, System.SysUtils,

  DUnitX.Loggers.Console, DUnitX.Loggers.XML.NUnit, DUnitX.TestFramework,
  TestGitParsing in '..\tests\TestGitParsing.pas',
  TestIgnoreRules in '..\tests\TestIgnoreRules.pas',
  TestPathUtils in '..\tests\TestPathUtils.pas';

var
  lRunner: ITestRunner;
  lResults: IRunResults;
  lLogger: ITestLogger;
  lXmlLogger: ITestLogger;
  lResultsPath: string;
  lResultsDir: string;

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    lRunner := TDUnitX.CreateRunner;
    lRunner.UseRTTI := True;

    lLogger := TDUnitXConsoleLogger.Create(True);
    lRunner.AddLogger(lLogger);

    lResultsPath := TPath.Combine(GetCurrentDir, 'TestResults.xml');
    lResultsDir := ExtractFilePath(lResultsPath);
    if (lResultsDir <> '') and (not DirectoryExists(lResultsDir)) then begin
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
    on E: Exception do begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
