program ScanGitRepos;

uses
  FastMM5 in 'F:\projects\3rdParty\FastMM5\FastMM5\FastMM5.pas',
  {$IFDEF madExcept}
  madExcept, madLinkDisAsm, madListHardware, madListModules, madListProcesses,
  MaxLogic.MadExcept.AiRunner,
  {$ENDIF}
  System.SysUtils,

  Vcl.Forms,

  maxLogic.ioutils, MaxLogic.Logger,

  UAppSettings in '..\src\UAppSettings.pas',
  UBulkActionResults in '..\src\UBulkActionResults.pas',
  UFolderSelection in '..\src\UFolderSelection.pas',
  UFolderTreeFrame in '..\src\UFolderTreeFrame.pas' {FolderTreeFrame: TFrame},
  UGitClient in '..\src\UGitClient.pas',
  UMainForm in '..\src\UMainForm.pas' {frmMain},
  UModels in '..\src\UModels.pas',
  UPathRules in '..\src\UPathRules.pas',
  URepoCache in '..\src\URepoCache.pas',
  URepoScanner in '..\src\URepoScanner.pas',
  URepositoryExclusionsDialog in '..\src\URepositoryExclusionsDialog.pas' {RepositoryExclusionsDialog},
  UScanPathsDialog in '..\src\UScanPathsDialog.pas' {frmScanPathsDialog},
  UStatusFilterHelp in '..\src\UStatusFilterHelp.pas' {frmStatusFilterHelp},
  UTextDetailsDialog in '..\src\UTextDetailsDialog.pas' {frmTextDetailsDialog},
  UTortoiseGit in '..\src\UTortoiseGit.pas',
  UUiEventQueue in '..\src\UUiEventQueue.pas';

{$R *.res}

var
  lExeDir: string;
  lLogDir: string;
begin
  {$IFDEF madExcept}
  MaxLogic.MadExcept.AiRunner.ConfigureFromEnvironment;
  {$ENDIF}
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
