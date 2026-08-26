program ScanGitRepos;

uses
  System.SysUtils,

  Vcl.Forms,

  madExcept, madLinkDisAsm, madListHardware, madListModules, madListProcesses,
  maxLogic.ioutils, MaxLogic.Logger,

  UAppSettings in '..\src\UAppSettings.pas',
  UGitClient in '..\src\UGitClient.pas',
  UMainForm in '..\src\UMainForm.pas' {frmMain},
  UModels in '..\src\UModels.pas',
  UPathRules in '..\src\UPathRules.pas',
  URepoCache in '..\src\URepoCache.pas',
  URepoScanner in '..\src\URepoScanner.pas',
  UScanPathsDialog in '..\src\UScanPathsDialog.pas' {frmScanPathsDialog},
  UTortoiseGit in '..\src\UTortoiseGit.pas',
  UUiEventQueue in '..\src\UUiEventQueue.pas';

{$R *.res}

var
  lExeDir: string;
  lLogDir: string;
begin
  lExeDir := ExtractFilePath(ParamStr(0));
  lLogDir := CombinePath([lExeDir, 'log']);
  SetGlobalMaxLog(TMaxLog.Create(10, 50 * 1024, lLogDir));
  maxLog.Info('ScanGitRepos starting.');

  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;

  maxLog.Info('ScanGitRepos shutting down.');
  ShutDownMaxLog;
end.
