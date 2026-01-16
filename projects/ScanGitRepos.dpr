program ScanGitRepos;

uses
   madExcept,
  madLinkDisAsm,
  madListHardware,
  madListProcesses,
  madListModules,
 System.SysUtils,
  Vcl.Forms,
  MaxLogic.Logger, maxLogic.ioutils,
  UMainForm in '..\src\UMainForm.pas' {frmMain},
  UAppSettings in '..\src\UAppSettings.pas',
  UGitClient in '..\src\UGitClient.pas',
  UModels in '..\src\UModels.pas',
  URepoCache in '..\src\URepoCache.pas',
  URepoScanner in '..\src\URepoScanner.pas',
  UUiEventQueue in '..\src\UUiEventQueue.pas',
  UPathRules in '..\src\UPathRules.pas';

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
