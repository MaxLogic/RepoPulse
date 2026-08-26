unit UMainForm;

interface

uses
  System.Classes, System.Diagnostics, System.Generics.Collections, System.ImageList, System.IOUtils,
  System.Skia, System.StrUtils, System.SyncObjs, System.SysUtils, System.Types,
  Winapi.ShellAPI, Winapi.Windows,
  Vcl.BaseImageCollection, Vcl.Clipbrd, Vcl.ComCtrls, Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls,
  Vcl.Forms, Vcl.Graphics, Vcl.ImgList, Vcl.Menus, Vcl.Skia, Vcl.StdCtrls, Vcl.VirtualImageList,
  AdvTypes, VirtualTrees, VirtualTrees.Accessibility,
  AutoFree, AutoHourGlass, CancelToken, MaxLogic.ApplicationMessageManager, MaxLogic.Logger,
  UAppSettings, UEscapeDialog, UGitClient, UModels, URepoListModel, URepoPathDisplay, URepoScanner,
  UScanPaths, UScanPathsDialog, UTortoiseGit, UUiEventQueue;

type
  {$SCOPEDENUMS ON}
  TRepoAction = (raPull, raCommit, raPush, raFetch, raFixSubmoduleMain, raRescan, raOpenFolder);
  TRepoFilter = (rfAttention, rfAll, rfDirty, rfBehind, rfDetached, rfClean);

  TfrmMain = class(TForm)
    pnlToolbar: TPanel;
    pnlToolbarContent: TPanel;
    pnlRootField: TPanel;
    edtStartPath: TEdit;
    lblStartPath: TStaticText;
    btnBrowseStart: TButton;
    pnlFilterField: TPanel;
    cboTargetName: TComboBox;
    lblTargetName: TStaticText;
    pnlStatusFilter: TPanel;
    cboStatusFilter: TComboBox;
    lblStatusFilter: TStaticText;
    pnlToolbarActions: TPanel;
    RepoTree: TVirtualStringTree;
    tmrUi: TTimer;
    btnScan: TButton;
    btnSettings: TButton;
    btnPullVisible: TButton;
    btnPushVisible: TButton;
    pnlStatus: TPanel;
    btnShowLog: TButton;
    stsMain: TStatusBar;
    pnlLogDrawer: TPanel;
    memLog: TMemo;
    pnlSettingsDrawer: TPanel;
    lblSettingsHeader: TStaticText;
    pnlSettingsContent: TPanel;
    pnlMaxDepthField: TPanel;
    edtMaxDepth: TEdit;
    lblMaxDepth: TStaticText;
    pnlThrottleField: TPanel;
    edtThrottle: TEdit;
    lblThrottle: TStaticText;
    pnlCacheField: TPanel;
    edtCacheTtl: TEdit;
    lblCacheTtl: TStaticText;
    pnlIgnoreDirs: TPanel;
    lblIgnoreDirs: TStaticText;
    btnEditIgnoreDirs: TButton;
    chkDebugLog: TCheckBox;
    pnlDebugPathField: TPanel;
    edtDebugLogPath: TEdit;
    lblDebugLogPath: TStaticText;
    pmRepoActions: TPopupMenu;
    miRepoCommit: TMenuItem;
    miRepoFetch: TMenuItem;
    miRepoFixSubmoduleMain: TMenuItem;
    miRepoSeparator: TMenuItem;
    miRepoTortoiseCommit: TMenuItem;
    miRepoTortoiseSync: TMenuItem;
    miRepoRescan: TMenuItem;
    miRepoOpenSeparator: TMenuItem;
    miRepoOpenFolder: TMenuItem;
    pbProgress: TProgressBar;
    ActivityPanel: TPanel;
    ScanAnimation: TSkAnimatedImage;
    lblScanActivity: TStaticText;
    ButtonImages: TVirtualImageList;
    ButtonSvgCollection: TAdvSVGImageCollection;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnBrowseStartClick(Sender: TObject);
    procedure btnScanClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnPullVisibleClick(Sender: TObject);
    procedure btnPushVisibleClick(Sender: TObject);
    procedure btnEditIgnoreDirsClick(Sender: TObject);
    procedure btnSettingsClick(Sender: TObject);
    procedure btnShowLogClick(Sender: TObject);
    procedure cboStatusFilterChange(Sender: TObject);
    procedure pnlStatusDblClick(Sender: TObject);
    procedure RepoMenuClick(Sender: TObject);
    procedure RepoActionsPopup(aSender: TObject);
    procedure RepoTreeAfterCellPaint(aSender: TBaseVirtualTree; aTargetCanvas: TCanvas;
      aNode: PVirtualNode; aColumn: TColumnIndex; aCellRect: TRect);
    procedure RepoTreeGetText(aSender: TBaseVirtualTree; aNode: PVirtualNode;
      aColumn: TColumnIndex; aTextType: TVSTTextType; var aCellText: string);
    procedure RepoTreeMouseDown(aSender: TObject; aButton: TMouseButton; aShift: TShiftState;
      X, Y: Integer);
    procedure RepoTreeMouseUp(aSender: TObject; aButton: TMouseButton; aShift: TShiftState;
      X, Y: Integer);
    procedure RepoTreePaintText(aSender: TBaseVirtualTree; const aTargetCanvas: TCanvas;
      aNode: PVirtualNode; aColumn: TColumnIndex; aTextType: TVSTTextType);
    procedure tmrUiTimer(Sender: TObject);
  private
    fSettings: TAppSettings;
    fGit: TGitClient;
    fScanner: TRepoScanner;
    fQueue: TUiEventQueue;
    fScanThread: TThread;
    fCancelToken: iCancelToken;
    fActionThreads: TList<TThread>;
    fActionLock: TCriticalSection;
    fActionBusyCount: Integer;
    fActionHourglass: IInterface;
    fShuttingDown: Boolean;
    fPopupRepoRoot: string;
    fTortoiseGitExe: string;
    fRepoStatusMap: TDictionary<string, TRepoStatus>;
    fRepoListModel: TRepoListModel;
    fStatusFilter: TRepoFilter;
    fScanGeneration: Int64;
    fMaxUiBatchMilliseconds: Int64;
    fUiMetricsPending: Boolean;
    fRepoViewDirty: Boolean;
    fRepoViewSelectionRoot: string;
    fLastRepoViewFlushTick: UInt64;
    fRedirectMouseWheel: TAppMessagehandlerRedirectMouseWheel;
    procedure LoadSettingsToUi;
    procedure UpdateScanPathsDisplay;
    function ReadSettingsFromUi(out aError: string): Boolean;
    function EditIgnoreDirsFile(const aPath: string): Boolean;
    function ResolveIgnoreDirsPath: string;
    function GetRelativeRepoPath(const aRepoRoot: string): string;
    function BuildDirtyBadge(const aDirtySummary: string; out aHasFiles: Boolean): string;
    procedure UpdateStatusFilterItems;
    procedure StartScan;
    procedure SetScanningState(const aScanning: Boolean);
    procedure BeginActionBusy;
    procedure EndActionBusy(const aCount: Integer = 1);
    procedure ClearRepoPanels;
    procedure AddWaitingRepo(const aRepoRoot: string);
    procedure AddRepoPanel(const aStatus: TRepoStatus);
    procedure UpdateRepoPanel(const aStatus: TRepoStatus);
    function RepoItemForNode(const aNode: PVirtualNode; out aItem: TRepoListItem): Boolean;
    function SelectedRepoRoot: string;
    procedure SelectRepoRoot(const aRepoRoot: string);
    procedure RefreshRepoTree(const aSelectionRoot: string = '');
    procedure QueueRepoViewRefresh;
    procedure FlushRepoView;
    function BuildRepoAccessibilityText(const aItem: TRepoListItem): string;
    procedure GetRepoActionRects(const aItem: TRepoListItem; const aCellRect: TRect;
      out aPullRect, aPushRect, aMoreRect: TRect);
    procedure PrepareRepoPopup(const aRepoRoot: string);
    procedure ShowRepoPopup(const aRepoRoot: string; const aPoint: TPoint);
    procedure HandleUiEvent(const aEvent: TUiEvent);
    procedure QueueLog(const aText: string);
    procedure ApplyStatusFilter;
    procedure UpdateBulkActionButtons;
    procedure CopyStatusToClipboard;
    procedure RunBulkAction(const aAction: TRepoAction);
    procedure AddActionThread(const aThread: TThread);
    procedure CleanupFinishedActionThreads;
    procedure WaitForActionThreads;
    procedure ScanThreadTerminated(Sender: TObject);
    procedure ExecuteRepoAction(const aAction: TRepoAction; const aRepoRoot: string);
    procedure UpdateStatusText(const aText: string);
    procedure RunRepoAction(const aAction: TRepoAction; const aRepoRoot: string; const aMessage: string);
  end;

var
  frmMain: TfrmMain;

implementation


uses
  {$IFDEF madExcept}
  MaxMadExcept,
  {$ENDIF}
  MaxLogic.ioUtils;

{$R *.dfm}

resourcestring
  rsFormCaption = 'RepoPulse - Scan Git Repos';
  rsSettingsHeader = 'Settings';
  rsStartPath = 'Scan Paths';
  rsStatusFilter = 'Status Filter';
  rsMaxDepth = 'Max depth';
  rsIgnoreDirsLabel = 'Ignore directory rules';
  rsEditIgnoreDirs = 'Edit ignore rules';
  rsIgnoreDialogTitle = 'Edit ignore directory rules';
  rsIgnoreLoadFailed = 'Failed to load ignore rules file: ';
  rsIgnoreSaveFailed = 'Failed to save ignore rules file: ';
  rsThrottle = 'Parallel Processing Limit';
  rsCacheTtl = 'Refresh Interval';
  rsDebugLog = 'Debug log';
  rsDebugLogPath = 'Debug log path';
  rsFilterAttention = 'Needs attention';
  rsFilterAll = 'All';
  rsFilterDirty = 'Dirty';
  rsFilterBehind = 'Behind';
  rsFilterDetached = 'Detached';
  rsFilterClean = 'Clean';
  rsFilterCountFmt = '%s (%d)';
  rsPullAll = 'Pull all';
  rsPushAll = 'Push all';
  rsRescanAction = 'Rescan';
  rsRescanCaption = '&Rescan';
  rsTortoiseGitCommit = 'TortoiseGit &Commit...';
  rsTortoiseGitSync = 'TortoiseGit &Sync...';

const
  rsTargetName = 'Search Filter';
  rsScan = 'Scan';
  rsScanActivity = 'Scanning repositories...';
  rsCancel = 'Cancel';
  rsSettings = 'Settings';
  rsShowLog = 'Show log';
  rsHideLog = 'Hide log';
  rsPull = 'Pull';
  rsCommit = 'Commit';
  rsPush = 'Push';
  rsFetch = 'Fetch';
  rsFixSubmoduleMain = 'Realign branch to remote main';
  rsOpenFolder = 'Open folder';
  rsCommitPrompt = 'Commit message:';
  rsCommitTitle = 'Commit';
  rsInvalidInput = 'Invalid input: ';
  rsOk = 'OK';
  rsScanPathsConfiguredFmt = '%d scan paths configured';
  rsErrMaxDepthNumber = 'MaxDepth must be a number';
  rsErrMaxDepthRange = 'MaxDepth must be >= 0';
  rsErrThrottleNumber = 'ThrottleLimit must be a number';
  rsErrThrottleRange = 'ThrottleLimit must be >= 1';
  rsErrCacheTtlNumber = 'CacheTtlSeconds must be a number';
  rsErrCacheTtlRange = 'CacheTtlSeconds must be >= 0';
  rsBadgeBranch = 'Branch: ';
  rsBadgeFetchFailed = 'Fetch failed';
  rsBadgeNoOrigin = 'No origin';
  rsBadgeNoUpstream = 'No upstream';
  rsBadgeBehind = 'Behind: ';
  rsBadgeAhead = 'Ahead: ';
  rsBadgeSyncOk = 'Clean';
  rsBadgeDirty = 'Dirty';
  rsBadgeSubmoduleNoFastForward = 'No fast-forward to ';
  rsStatusReady = 'Ready';
  rsStatusScanning = 'Scanning...';
  rsStatusWaiting = 'Waiting for status...';
  rsFixSubmoduleMissingRef = 'Cannot realign the branch because origin/main and origin/master are missing.';
  rsFixSubmoduleConfirm = 'This will run "git fetch --prune origin", "git reset --hard %s", and "git checkout -B %s %s".'#13#10 +
    'This discards local commits/changes in that repo. Continue?';
  rsPullConflictAlert = 'Pull failed due to conflicts/non-fast-forward in:' + #13#10 + '%s' + #13#10#13#10 + '%s';

const
  cLogScanStarted = 'Scan started.';
  cLogScanCancelled = 'Cancel requested.';
  cLogAction = 'Action';
  cLogActionOk = 'OK';
  cLogActionFailed = 'FAILED';
  cLogParentRefreshFailed = 'Parent refresh failed: %s';
  cIgnoreFileName = '.ignoredirectory';
  cMaxUiEventsPerTick = 64;
  cMaxUiMillisecondsPerTick = 8;
  cBusyUiTimerInterval = 1;
  cIdleUiTimerInterval = 100;
  cRepoViewFlushInterval = 100;
  cLogUiMetrics = 'UI event metrics: queue peak %d, max batch %d ms';

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  {$IFDEF madExcept}
  MaxMadExcept.AdjustMadExcept(GetInstallDir);
  {$ENDIF}
  fSettings := TAppSettings.Create;
  fSettings.Load;

  fGit := TGitClient.Create;
  fScanner := TRepoScanner.Create(fGit);
  fQueue := TUiEventQueue.Create;
  fRepoStatusMap := TDictionary<string, TRepoStatus>.Create;
  fRepoListModel := TRepoListModel.Create;
  fActionThreads := TList<TThread>.Create;
  fActionLock := TCriticalSection.Create;
  fShuttingDown := False;
  fTortoiseGitExe := TTortoiseGit.DetectExecutable;

  Caption := rsFormCaption;
  lblSettingsHeader.Caption := rsSettingsHeader;
  lblStartPath.Caption := rsStartPath;
  lblMaxDepth.Caption := rsMaxDepth;
  lblIgnoreDirs.Caption := rsIgnoreDirsLabel + ' (' + cIgnoreFileName + ')';
  btnEditIgnoreDirs.Caption := rsEditIgnoreDirs;
  lblThrottle.Caption := rsThrottle;
  lblCacheTtl.Caption := rsCacheTtl;
  chkDebugLog.Caption := rsDebugLog;
  lblDebugLogPath.Caption := rsDebugLogPath;
  lblTargetName.Caption := rsTargetName;
  lblStatusFilter.Caption := rsStatusFilter;

  btnScan.Caption := rsScan;
  lblScanActivity.Caption := rsScanActivity;
  btnSettings.Caption := rsSettings;
  btnShowLog.Caption := rsShowLog;
  btnPullVisible.Caption := rsPullAll;
  btnPushVisible.Caption := rsPushAll;
  miRepoCommit.Caption := rsCommit;
  miRepoFetch.Caption := rsFetch;
  miRepoFixSubmoduleMain.Caption := rsFixSubmoduleMain;
  miRepoTortoiseCommit.Caption := rsTortoiseGitCommit;
  miRepoTortoiseSync.Caption := rsTortoiseGitSync;
  miRepoRescan.Caption := rsRescanCaption;
  miRepoOpenFolder.Caption := rsOpenFolder;
  miRepoTortoiseCommit.Visible := fTortoiseGitExe <> '';
  miRepoTortoiseSync.Visible := fTortoiseGitExe <> '';

  cboStatusFilter.Items.BeginUpdate;
  try
    cboStatusFilter.Items.Clear;
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterAttention, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterAll, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterDirty, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterBehind, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterDetached, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterClean, 0]));
    cboStatusFilter.ItemIndex := 0;
  finally
    cboStatusFilter.Items.EndUpdate;
  end;
  fStatusFilter := TRepoFilter.rfAttention;

  LoadSettingsToUi;
  SetScanningState(False);
  pbProgress.Visible := False;
  fRedirectMouseWheel := TAppMessagehandlerRedirectMouseWheel.Create;
  tmrUi.Interval := 100;
  tmrUi.Enabled := True;
  UpdateStatusText(rsStatusReady);
  UpdateBulkActionButtons;
  UpdateStatusFilterItems;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  fShuttingDown := True;
  tmrUi.Enabled := False;
  ScanAnimation.Animation.Loop := False;
  ScanAnimation.Animation.Enabled := False;
  FreeAndNil(fRedirectMouseWheel);

  if fScanThread <> nil then
  begin
    if fCancelToken <> nil then
    begin
      fCancelToken.Cancel;
    end;
    fScanThread.WaitFor;
  end;
  fCancelToken := nil;
  WaitForActionThreads;
  fRepoListModel.Free;
  fRepoStatusMap.Free;
  fQueue.Free;
  fScanner.Free;
  fGit.Free;
  fSettings.Free;
  fActionLock.Free;
  fActionThreads.Free;
end;

procedure TfrmMain.LoadSettingsToUi;
var
  i: Integer;
begin
  UpdateScanPathsDisplay;
  edtMaxDepth.Text := IntToStr(fSettings.MaxDepth);
  edtThrottle.Text := IntToStr(fSettings.ThrottleLimit);
  edtCacheTtl.Text := IntToStr(fSettings.CacheTtlSeconds);
  chkDebugLog.Checked := fSettings.DebugLogEnabled;
  edtDebugLogPath.Text := fSettings.DebugLogPath;

  cboTargetName.Items.BeginUpdate;
  try
    cboTargetName.Items.Clear;
    for i := 0 to Length(fSettings.RepoNameHistory) - 1 do
      cboTargetName.Items.Add(fSettings.RepoNameHistory[i]);
  finally
    cboTargetName.Items.EndUpdate;
  end;
  cboTargetName.Text := fSettings.TargetRepoName;
end;

procedure TfrmMain.UpdateScanPathsDisplay;
var
  g: TGarbos;
  lPaths: TStringList;
  lPath: string;
begin
  if Length(fSettings.ScanPaths) = 1 then
    edtStartPath.Text := fSettings.ScanPaths[0]
  else
    edtStartPath.Text := Format(rsScanPathsConfiguredFmt, [Length(fSettings.ScanPaths)]);

  GC(lPaths, TStringList.Create, g);
  for lPath in fSettings.ScanPaths do
    lPaths.Add(lPath);
  edtStartPath.Hint := Trim(lPaths.Text);
end;

function TfrmMain.ReadSettingsFromUi(out aError: string): Boolean;
var
  g: TGarbos;
  lNum: Integer;
  i: Integer;
  lHistory: TList<string>;
  lFound: Boolean;
  lItem: string;
  lRepoNameHistory: TArray<string>;
  lPathLines: TStringList;
  lScanPaths: TArray<string>;
  lScanPath: string;
begin
  aError := '';
  Result := False;

  GC(lPathLines, TStringList.Create, g);
  for lScanPath in fSettings.ScanPaths do
    lPathLines.Add(lScanPath);
  if not TryNormalizeScanPaths(lPathLines, lScanPaths, aError) then
    Exit(False);
  fSettings.ScanPaths := lScanPaths;
  fSettings.StartPath := lScanPaths[0];
  UpdateScanPathsDisplay;

  if not TryStrToInt(Trim(edtMaxDepth.Text), lNum) then
  begin
    aError := rsErrMaxDepthNumber;
    Exit(False);
  end;
  if lNum < 0 then
  begin
    aError := rsErrMaxDepthRange;
    Exit(False);
  end;
  fSettings.MaxDepth := lNum;

  if not TryStrToInt(Trim(edtThrottle.Text), lNum) then
  begin
    aError := rsErrThrottleNumber;
    Exit(False);
  end;
  if lNum < 1 then
  begin
    aError := rsErrThrottleRange;
    Exit(False);
  end;
  fSettings.ThrottleLimit := lNum;

  if not TryStrToInt(Trim(edtCacheTtl.Text), lNum) then
  begin
    aError := rsErrCacheTtlNumber;
    Exit(False);
  end;
  if lNum < 0 then
  begin
    aError := rsErrCacheTtlRange;
    Exit(False);
  end;
  fSettings.CacheTtlSeconds := lNum;

  fSettings.DebugLogEnabled := chkDebugLog.Checked;
  fSettings.DebugLogPath := Trim(edtDebugLogPath.Text);

  fSettings.TargetRepoName := Trim(cboTargetName.Text);
  if fSettings.TargetRepoName = '' then
  begin
    fSettings.TargetRepoName := '*';
    cboTargetName.Text := fSettings.TargetRepoName;
  end;

  GC(lHistory, TList<string>.Create, g);
  for i := 0 to Length(fSettings.RepoNameHistory) - 1 do
    lHistory.Add(fSettings.RepoNameHistory[i]);

  lFound := False;
  for lItem in lHistory do
  begin
    if SameText(lItem, fSettings.TargetRepoName) then
    begin
      lFound := True;
      Break;
    end;
  end;
  if not lFound then
    lHistory.Insert(0, fSettings.TargetRepoName);

  SetLength(lRepoNameHistory, lHistory.Count);
  for i := 0 to lHistory.Count - 1 do
    lRepoNameHistory[i] := lHistory[i];
  fSettings.RepoNameHistory := lRepoNameHistory;

  cboTargetName.Items.BeginUpdate;
  try
    cboTargetName.Items.Clear;
    for i := 0 to Length(fSettings.RepoNameHistory) - 1 do
      cboTargetName.Items.Add(fSettings.RepoNameHistory[i]);
  finally
    cboTargetName.Items.EndUpdate;
  end;
  cboTargetName.Text := fSettings.TargetRepoName; // restore, as items.clear clears also the text property

  Result := True;
end;

function TfrmMain.ResolveIgnoreDirsPath: string;
var
  lSettingsFolder: string;
  lExeFolder: string;
  lSettingsPath: string;
  lExePath: string;
begin
  lSettingsFolder := TAppSettings.GetSettingsFolder;
  lExeFolder := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  lSettingsPath := CombinePath([lSettingsFolder, cIgnoreFileName]);
  lExePath := CombinePath([lExeFolder, cIgnoreFileName]);

  if FileExists(lSettingsPath) then
    Exit(lSettingsPath);
  if FileExists(lExePath) then
    Exit(lExePath);

  Result := lSettingsPath;
end;


function TfrmMain.GetRelativeRepoPath(const aRepoRoot: string): string;
begin
  Result := BuildRelativeRepoPath(aRepoRoot, fSettings.ScanPaths);
end;

function TfrmMain.BuildDirtyBadge(const aDirtySummary: string; out aHasFiles: Boolean): string;
var
  lText: string;
  lParts: TArray<string>;
  lFiles: TList<string>;
  g: TGarbos;
  lItem: string;
  lTrimmed: string;
  lOut: TStringList;
  lExtra: Integer;
  lToken: string;
  lPos: Integer;
begin
  aHasFiles := False;
  lText := Trim(aDirtySummary);
  if lText = '' then
  begin
    Result := rsBadgeDirty;
    Exit;
  end;

  lText := StringReplace(lText, #13#10, ',', [rfReplaceAll]);
  lText := StringReplace(lText, #10, ',', [rfReplaceAll]);
  lText := StringReplace(lText, ';', ',', [rfReplaceAll]);
  lText := StringReplace(lText, '|', ',', [rfReplaceAll]);

  lParts := SplitString(lText, ',');
  GC(lFiles, TList<string>.Create, g);
  for lItem in lParts do
  begin
    lTrimmed := Trim(lItem);
    if lTrimmed = '' then
      Continue;
    if (Length(lTrimmed) >= 3) and (lTrimmed[3] = ' ') then
      lTrimmed := Trim(Copy(lTrimmed, 4, MaxInt))
    else begin
      lPos := LastDelimiter(' ', lTrimmed);
      if lPos > 0 then
      begin
        lToken := Trim(Copy(lTrimmed, lPos + 1, MaxInt));
        if lToken <> '' then
          lTrimmed := lToken;
      end;
    end;
    if lTrimmed <> '' then
      lFiles.Add(lTrimmed);
  end;

  if lFiles.Count = 0 then
  begin
    Result := rsBadgeDirty;
    Exit;
  end;

  aHasFiles := True;
  GC(lOut, TStringList.Create, g);
  lOut.Delimiter := ',';
  lOut.StrictDelimiter := True;
  lExtra := 0;
  for lItem in lFiles do
  begin
    if lOut.Count < 3 then
      lOut.Add(lItem)
    else
      Inc(lExtra);
  end;

  Result := rsBadgeDirty + ': ' + StringReplace(lOut.CommaText, ',', ', ', [rfReplaceAll]);
  if lExtra > 0 then
    Result := Result + ' +' + IntToStr(lExtra);
end;


procedure TfrmMain.UpdateStatusText(const aText: string);
begin
  stsMain.SimpleText := aText;
end;

procedure TfrmMain.ApplyStatusFilter;
var
  lSelectedRoot: string;
begin
  lSelectedRoot := SelectedRepoRoot;
  fRepoListModel.SetFilter(TRepoListFilter(Ord(fStatusFilter)));
  RefreshRepoTree(lSelectedRoot);
  UpdateBulkActionButtons;
  UpdateStatusFilterItems;
end;

procedure TfrmMain.UpdateStatusFilterItems;
var
  lAttention: Integer;
  lAll: Integer;
  lDirty: Integer;
  lBehind: Integer;
  lDetached: Integer;
  lClean: Integer;
  lIndex: Integer;
begin
  lAttention := fRepoListModel.FilterCount(TRepoListFilter.rlfAttention);
  lAll := fRepoListModel.FilterCount(TRepoListFilter.rlfAll);
  lDirty := fRepoListModel.FilterCount(TRepoListFilter.rlfDirty);
  lBehind := fRepoListModel.FilterCount(TRepoListFilter.rlfBehind);
  lDetached := fRepoListModel.FilterCount(TRepoListFilter.rlfDetached);
  lClean := fRepoListModel.FilterCount(TRepoListFilter.rlfClean);

  lIndex := cboStatusFilter.ItemIndex;
  cboStatusFilter.Items.BeginUpdate;
  try
    if cboStatusFilter.Items.Count <> 6 then
      cboStatusFilter.Items.Clear;
    if cboStatusFilter.Items.Count = 6 then
    begin
      cboStatusFilter.Items[0] := Format(rsFilterCountFmt, [rsFilterAttention, lAttention]);
      cboStatusFilter.Items[1] := Format(rsFilterCountFmt, [rsFilterAll, lAll]);
      cboStatusFilter.Items[2] := Format(rsFilterCountFmt, [rsFilterDirty, lDirty]);
      cboStatusFilter.Items[3] := Format(rsFilterCountFmt, [rsFilterBehind, lBehind]);
      cboStatusFilter.Items[4] := Format(rsFilterCountFmt, [rsFilterDetached, lDetached]);
      cboStatusFilter.Items[5] := Format(rsFilterCountFmt, [rsFilterClean, lClean]);
    end else begin
      cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterAttention, lAttention]));
      cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterAll, lAll]));
      cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterDirty, lDirty]));
      cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterBehind, lBehind]));
      cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterDetached, lDetached]));
      cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterClean, lClean]));
    end;
  finally
    cboStatusFilter.Items.EndUpdate;
  end;
  if (lIndex >= 0) and (lIndex < cboStatusFilter.Items.Count) then
    cboStatusFilter.ItemIndex := lIndex
  else if cboStatusFilter.Items.Count > 0 then
    cboStatusFilter.ItemIndex := 0;
end;

procedure TfrmMain.UpdateBulkActionButtons;
var
  i: Integer;
  lItem: TRepoListItem;
  lHasPull: Boolean;
  lHasPush: Boolean;
begin
  lHasPull := False;
  lHasPush := False;
  for i := 0 to fRepoListModel.VisibleCount - 1 do
  begin
    lItem := fRepoListModel.ItemAtVisible(i);
    if lItem.State <> TRepoListItemState.rlisReady then
      Continue;
    if lItem.Status.IsOutOfDate then
      lHasPull := True;
    if lItem.Status.IsDirty then
      lHasPush := True;
    if lHasPull and lHasPush then
      Break;
  end;
  btnPullVisible.Enabled := lHasPull and (fScanThread = nil);
  btnPushVisible.Enabled := lHasPush and (fScanThread = nil);
end;

procedure TfrmMain.CopyStatusToClipboard;
var
  lText: string;
begin
  lText := Trim(stsMain.SimpleText);
  if lText = '' then
    Exit;
  Clipboard.AsText := lText;
end;

procedure TfrmMain.RunBulkAction(const aAction: TRepoAction);
var
  i: Integer;
  lItem: TRepoListItem;
begin
  for i := 0 to fRepoListModel.VisibleCount - 1 do
  begin
    lItem := fRepoListModel.ItemAtVisible(i);
    if lItem.State <> TRepoListItemState.rlisReady then
      Continue;
    case aAction of
      TRepoAction.raPull:
        if not lItem.Status.IsOutOfDate then
          Continue;
      TRepoAction.raPush:
        if not lItem.Status.IsDirty then
          Continue;
    else
      Continue;
    end;
    ExecuteRepoAction(aAction, lItem.RepoRoot);
  end;
end;

function TfrmMain.EditIgnoreDirsFile(const aPath: string): Boolean;
var
  g: TGarbos;
  lForm: TEscapeDialogForm;
  lMemo: TMemo;
  lPanel: TPanel;
  lOk: TButton;
  lCancel: TButton;
  lFolder: string;
  i: Integer;
begin
  Result := False;

  GC(lForm, TEscapeDialogForm.CreateNew(nil), g);
  lForm.KeyPreview := True;
  lForm.Caption := rsIgnoreDialogTitle;
  lForm.BorderStyle := bsDialog;
  lForm.Position := poOwnerFormCenter;
  lForm.ClientWidth := 700;
  lForm.ClientHeight := 420;
  lForm.Font.Assign(Font);

  lPanel := TPanel.Create(lForm);
  lPanel.Parent := lForm;
  lPanel.Align := alBottom;
  lPanel.Height := 42;
  lPanel.BevelOuter := bvNone;

  lOk := TButton.Create(lForm);
  lOk.Parent := lPanel;
  lOk.Caption := rsOk;
  lOk.ModalResult := mrOk;
  lOk.Default := True;
  lOk.Width := 90;
  lOk.Height := 27;
  lOk.Top := 8;
  lOk.Left := lPanel.ClientWidth - lOk.Width - 8;
  lOk.Anchors := [akRight, akBottom];

  lCancel := TButton.Create(lForm);
  lCancel.Parent := lPanel;
  lCancel.Caption := rsCancel;
  lCancel.ModalResult := mrCancel;
  lCancel.Cancel := True;
  lCancel.Width := 90;
  lCancel.Height := 27;
  lCancel.Top := 8;
  lCancel.Left := lOk.Left - lCancel.Width - 8;
  lCancel.Anchors := [akRight, akBottom];

  lMemo := TMemo.Create(lForm);
  lMemo.Parent := lForm;
  lMemo.Align := alClient;
  lMemo.ScrollBars := ssBoth;
  lMemo.WordWrap := False;

  if FileExists(aPath) then
  begin
    try
      lMemo.Lines.LoadFromFile(aPath, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        MessageDlg(rsIgnoreLoadFailed + E.Message, mtError, [mbOk], 0);
        Exit(False);
      end;
    end;
  end else if Length(fSettings.ExcludeDirs) > 0 then
  begin
    lMemo.Lines.BeginUpdate;
    try
      lMemo.Lines.Clear;
      for i := 0 to Length(fSettings.ExcludeDirs) - 1 do
        lMemo.Lines.Add(fSettings.ExcludeDirs[i]);
    finally
      lMemo.Lines.EndUpdate;
    end;
  end;

  lForm.ActiveControl := lMemo;

  if lForm.ShowModal <> mrOk then
    Exit(False);

  lFolder := ExcludeTrailingPathDelimiter(ExtractFilePath(aPath));
  if (lFolder <> '') and (not DirectoryExists(lFolder)) then
    ForceDirectories(lFolder);

  try
    lMemo.Lines.SaveToFile(aPath, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      MessageDlg(rsIgnoreSaveFailed + E.Message, mtError, [mbOk], 0);
      Exit(False);
    end;
  end;

  Result := True;
end;

procedure TfrmMain.SetScanningState(const aScanning: Boolean);
begin
  ActivityPanel.Visible := aScanning;
  ScanAnimation.Visible := aScanning;
  if aScanning then
  begin
    ScanAnimation.Animation.Loop := True;
    ScanAnimation.Animation.Enabled := True;
    ScanAnimation.Animation.Start;
    btnScan.Caption := rsCancel;
    btnScan.OnClick := btnCancelClick;
  end else begin
    ScanAnimation.Animation.Loop := False;
    ScanAnimation.Animation.Enabled := False;
    btnScan.Caption := rsScan;
    btnScan.OnClick := btnScanClick;
  end;
  btnSettings.Enabled := not aScanning;
  btnBrowseStart.Enabled := not aScanning;
  cboTargetName.Enabled := not aScanning;
  if aScanning then
  begin
    btnPullVisible.Enabled := False;
    btnPushVisible.Enabled := False;
  end else begin
    UpdateBulkActionButtons;
  end;
end;

procedure TfrmMain.BeginActionBusy;
begin
  Inc(fActionBusyCount);
  if fActionBusyCount = 1 then
    fActionHourglass := AutoHourGlass.MakeCHG;
end;

procedure TfrmMain.EndActionBusy(const aCount: Integer);
begin
  if aCount <= 0 then
    Exit;
  Dec(fActionBusyCount, aCount);
  if fActionBusyCount < 0 then
    fActionBusyCount := 0;
  if fActionBusyCount = 0 then
    fActionHourglass := nil;
end;

procedure TfrmMain.ClearRepoPanels;
begin
  fRepoViewDirty := False;
  fRepoViewSelectionRoot := '';
  fLastRepoViewFlushTick := 0;
  fRepoListModel.Clear;
  fRepoStatusMap.Clear;
  RepoTree.Clear;
  UpdateBulkActionButtons;
  UpdateStatusFilterItems;
end;

procedure TfrmMain.AddWaitingRepo(const aRepoRoot: string);
var
  lCount: Integer;
begin
  lCount := fRepoListModel.Count;
  fRepoListModel.AddWaiting(aRepoRoot, GetRelativeRepoPath(aRepoRoot));
  if fRepoListModel.Count <> lCount then
    QueueRepoViewRefresh;
end;

procedure TfrmMain.AddRepoPanel(const aStatus: TRepoStatus);
begin
  fRepoStatusMap.AddOrSetValue(aStatus.RepoRoot, aStatus);
  fRepoListModel.AddOrUpdate(aStatus, GetRelativeRepoPath(aStatus.RepoRoot));
  QueueRepoViewRefresh;
end;

procedure TfrmMain.UpdateRepoPanel(const aStatus: TRepoStatus);
begin
  AddRepoPanel(aStatus);
end;

function TfrmMain.RepoItemForNode(const aNode: PVirtualNode; out aItem: TRepoListItem): Boolean;
begin
  Result := (aNode <> nil) and (aNode.Index < Cardinal(fRepoListModel.VisibleCount));
  if Result then
    aItem := fRepoListModel.ItemAtVisible(aNode.Index)
  else
    aItem := Default(TRepoListItem);
end;

function TfrmMain.SelectedRepoRoot: string;
var
  lItem: TRepoListItem;
begin
  Result := '';
  if RepoItemForNode(RepoTree.FocusedNode, lItem) then
    Result := lItem.RepoRoot;
end;

procedure TfrmMain.SelectRepoRoot(const aRepoRoot: string);
var
  lIndex: Integer;
  lNode: PVirtualNode;
begin
  if aRepoRoot = '' then
    Exit;
  lIndex := fRepoListModel.FindVisibleIndex(aRepoRoot);
  if lIndex < 0 then
    Exit;
  lNode := RepoTree.GetFirst;
  while (lNode <> nil) and (Integer(lNode.Index) <> lIndex) do
    lNode := RepoTree.GetNextSibling(lNode);
  if lNode = nil then
    Exit;
  RepoTree.FocusedNode := lNode;
  RepoTree.Selected[lNode] := True;
  RepoTree.ScrollIntoView(lNode, False);
end;

procedure TfrmMain.RefreshRepoTree(const aSelectionRoot: string);
begin
  RepoTree.BeginUpdate;
  try
    RepoTree.RootNodeCount := fRepoListModel.VisibleCount;
    RepoTree.Invalidate;
  finally
    RepoTree.EndUpdate;
  end;
  SelectRepoRoot(aSelectionRoot);
end;

procedure TfrmMain.QueueRepoViewRefresh;
begin
  if not fRepoViewDirty then
    fRepoViewSelectionRoot := SelectedRepoRoot;
  fRepoViewDirty := True;
end;

procedure TfrmMain.FlushRepoView;
begin
  if not fRepoViewDirty then
    Exit;
  fRepoViewDirty := False;
  RefreshRepoTree(fRepoViewSelectionRoot);
  fRepoViewSelectionRoot := '';
  fLastRepoViewFlushTick := GetTickCount64;
  UpdateBulkActionButtons;
  UpdateStatusFilterItems;
end;

function TfrmMain.BuildRepoAccessibilityText(const aItem: TRepoListItem): string;
var
  lDirty: string;
  lHasFiles: Boolean;
begin
  Result := aItem.DisplayPath;
  if aItem.State = TRepoListItemState.rlisWaiting then
    Exit(Result + '. ' + rsStatusWaiting);
  Result := Result + '. ' + rsBadgeBranch + aItem.Status.Branch;
  if aItem.Status.FetchFailed then
    Result := Result + '. ' + rsBadgeFetchFailed
  else if not aItem.Status.HasOrigin then
    Result := Result + '. ' + rsBadgeNoOrigin
  else if aItem.Status.Upstream = '' then
    Result := Result + '. ' + rsBadgeNoUpstream
  else if aItem.Status.IsOutOfDate then
    Result := Result + '. ' + rsBadgeBehind + IntToStr(aItem.Status.Behind)
  else if aItem.Status.HasUnpushed then
    Result := Result + '. ' + rsBadgeAhead + IntToStr(aItem.Status.Ahead)
  else
    Result := Result + '. ' + rsBadgeSyncOk;
  if aItem.Status.SubmoduleNeedsMainFastForward then
    Result := Result + '. ' + rsBadgeSubmoduleNoFastForward + aItem.Status.SubmoduleMainRemoteRef;
  if aItem.Status.IsDirty then
  begin
    lDirty := BuildDirtyBadge(aItem.Status.DirtySummary, lHasFiles);
    Result := Result + '. ' + lDirty;
  end;
end;

procedure TfrmMain.GetRepoActionRects(const aItem: TRepoListItem; const aCellRect: TRect;
  out aPullRect, aPushRect, aMoreRect: TRect);
var
  lRight: Integer;
  lTop: Integer;
begin
  aPullRect := Rect(0, 0, 0, 0);
  aPushRect := Rect(0, 0, 0, 0);
  lRight := aCellRect.Right - 12;
  lTop := aCellRect.Top + ((aCellRect.Height - 30) div 2);
  aMoreRect := Rect(lRight - 30, lTop, lRight, lTop + 30);
  lRight := aMoreRect.Left - 6;
  if aItem.State <> TRepoListItemState.rlisReady then
    Exit;
  if aItem.Status.IsDirty then
  begin
    aPushRect := Rect(lRight - 30, lTop, lRight, lTop + 30);
    lRight := aPushRect.Left - 6;
  end;
  if aItem.Status.IsOutOfDate then
    aPullRect := Rect(lRight - 30, lTop, lRight, lTop + 30);
end;

procedure TfrmMain.ShowRepoPopup(const aRepoRoot: string; const aPoint: TPoint);
begin
  if aRepoRoot = '' then
    Exit;
  PrepareRepoPopup(aRepoRoot);
  pmRepoActions.Popup(aPoint.X, aPoint.Y);
end;

procedure TfrmMain.PrepareRepoPopup(const aRepoRoot: string);
var
  lStatus: TRepoStatus;
begin
  fPopupRepoRoot := aRepoRoot;
  if fRepoStatusMap.TryGetValue(aRepoRoot, lStatus) then
  begin
    miRepoCommit.Visible := lStatus.IsDirty;
    miRepoFixSubmoduleMain.Visible := lStatus.SubmoduleNeedsMainFastForward;
  end else begin
    miRepoCommit.Visible := False;
    miRepoFixSubmoduleMain.Visible := False;
  end;
  miRepoTortoiseCommit.Visible := fTortoiseGitExe <> '';
  miRepoTortoiseSync.Visible := fTortoiseGitExe <> '';
end;

procedure TfrmMain.HandleUiEvent(const aEvent: TUiEvent);
begin
  case aEvent.Kind of
    TUiEventKind.uekLog:
      begin
        memLog.Lines.Add(aEvent.Text);
        UpdateStatusText(aEvent.Text);
      end;
    TUiEventKind.uekProgressStart:
      begin
        pbProgress.Visible := True;
        if aEvent.ProgressMode = TProgressMode.pmIndeterminate then
        begin
          pbProgress.Style := pbstMarquee;
        end else begin
          pbProgress.Style := pbstNormal;
          pbProgress.Max := aEvent.ProgressMax;
          pbProgress.Position := aEvent.ProgressValue;
        end;
        UpdateStatusText(rsStatusScanning);
      end;
    TUiEventKind.uekProgressUpdate:
      begin
        if pbProgress.Style = pbstNormal then
          pbProgress.Position := aEvent.ProgressValue;
      end;
    TUiEventKind.uekProgressEnd:
      begin
        pbProgress.Visible := False;
        pbProgress.Position := 0;
      end;
    TUiEventKind.uekRepoWaiting:
      AddWaitingRepo(aEvent.RepoRoot);
    TUiEventKind.uekRepoResult:
      AddRepoPanel(aEvent.RepoStatus);
    TUiEventKind.uekScanFinished:
      begin
        memLog.Lines.Add(aEvent.Text);
        UpdateStatusText(aEvent.Text);
        SetScanningState(False);
        UpdateStatusFilterItems;
      end;
    TUiEventKind.uekActionResult:
      begin
        memLog.Lines.Add(aEvent.Text);
        UpdateStatusText(aEvent.Text);
        if aEvent.RepoStatus.RepoRoot <> '' then
          UpdateRepoPanel(aEvent.RepoStatus);
        if aEvent.RelatedRepoStatus.RepoRoot <> '' then
          UpdateRepoPanel(aEvent.RelatedRepoStatus);
        if aEvent.AlertText <> '' then
          MessageDlg(aEvent.AlertText, mtWarning, [mbOK], 0);
      end;
    TUiEventKind.uekClearResults:
      ClearRepoPanels;
  end;
end;

procedure TfrmMain.QueueLog(const aText: string);
var
  lEvent: TUiEvent;
begin
  maxLog.Info(aText);
  lEvent := Default(TUiEvent);
  lEvent.Kind := TUiEventKind.uekLog;
  lEvent.Generation := fScanGeneration;
  lEvent.Text := aText;
  fQueue.Enqueue(lEvent);
end;

procedure TfrmMain.StartScan;
var
  lEvent: TUiEvent;
  lGeneration: Int64;
begin
  if fScanThread <> nil then
    Exit;

  ClearRepoPanels;
  memLog.Clear;
  UpdateStatusText(rsStatusScanning);
  Inc(fScanGeneration);
  fMaxUiBatchMilliseconds := 0;
  fUiMetricsPending := True;
  fQueue.ResetPeakCount;
  lGeneration := fScanGeneration;
  QueueLog(cLogScanStarted);

  fCancelToken := TCancelToken.Create;
  SetScanningState(True);

  lEvent := Default(TUiEvent);
  lEvent.Kind := TUiEventKind.uekClearResults;
  lEvent.Generation := lGeneration;
  fQueue.Enqueue(lEvent);

  fScanThread := TThread.CreateAnonymousThread(
    procedure
    var
      lErrEvent: TUiEvent;
    begin
      try
        fScanner.ExecuteScan(fSettings, fQueue, fCancelToken, lGeneration);
      except
        on E: Exception do
        begin
          lErrEvent := Default(TUiEvent);
          lErrEvent.Kind := TUiEventKind.uekLog;
          lErrEvent.Generation := lGeneration;
          lErrEvent.Text := 'Scan failed: ' + E.ClassName + ' - ' + E.Message;
          fQueue.Enqueue(lErrEvent);
          raise;
        end;
      end;
    end
  );
  fScanThread.FreeOnTerminate := True;
  fScanThread.OnTerminate := ScanThreadTerminated;
  fScanThread.Start;
end;

procedure TfrmMain.ScanThreadTerminated(Sender: TObject);
begin
  fScanThread := nil;
  fCancelToken := nil;
  SetScanningState(False);
end;

procedure TfrmMain.RepoTreeGetText(aSender: TBaseVirtualTree; aNode: PVirtualNode;
  aColumn: TColumnIndex; aTextType: TVSTTextType; var aCellText: string);
var
  lItem: TRepoListItem;
begin
  aCellText := '';
  if RepoItemForNode(aNode, lItem) then
    aCellText := BuildRepoAccessibilityText(lItem);
end;

procedure TfrmMain.RepoTreePaintText(aSender: TBaseVirtualTree; const aTargetCanvas: TCanvas;
  aNode: PVirtualNode; aColumn: TColumnIndex; aTextType: TVSTTextType);
begin
  aTargetCanvas.Font.Color := aTargetCanvas.Brush.Color;
  aTargetCanvas.Font.Height := -1;
end;

procedure TfrmMain.RepoTreeAfterCellPaint(aSender: TBaseVirtualTree; aTargetCanvas: TCanvas;
  aNode: PVirtualNode; aColumn: TColumnIndex; aCellRect: TRect);
var
  lItem: TRepoListItem;
  lPullRect: TRect;
  lPushRect: TRect;
  lMoreRect: TRect;
  lTextRect: TRect;
  lBadgeRect: TRect;
  lDirty: string;
  lHasFiles: Boolean;
  lBadgeX: Integer;
  lBadgeRight: Integer;
  lTextColor: TColor;
  lSavedDc: Integer;

  procedure DrawBadge(const aCaption: string; const aAlert: Boolean);
  var
    lWidth: Integer;
  begin
    lWidth := aTargetCanvas.TextWidth(aCaption) + 16;
    if lBadgeX + lWidth > lBadgeRight then
      Exit;
    lBadgeRect := Rect(lBadgeX, aCellRect.Top + 34, lBadgeX + lWidth, aCellRect.Top + 56);
    if aAlert then
      aTargetCanvas.Brush.Color := $00E7E7FF
    else
      aTargetCanvas.Brush.Color := $00F1F1F1;
    aTargetCanvas.Pen.Color := $00D0D0D0;
    aTargetCanvas.RoundRect(lBadgeRect.Left, lBadgeRect.Top, lBadgeRect.Right,
      lBadgeRect.Bottom, 8, 8);
    aTargetCanvas.Brush.Style := bsClear;
    aTargetCanvas.Font.Color := clWindowText;
    aTargetCanvas.TextOut(lBadgeRect.Left + 8, lBadgeRect.Top + 3, aCaption);
    aTargetCanvas.Brush.Style := bsSolid;
    Inc(lBadgeX, lWidth + 6);
  end;

  procedure DrawAction(const aRect: TRect; const aImageIndex: Integer);
  var
    lImageRect: TRect;
  begin
    if IsRectEmpty(aRect) then
      Exit;
    aTargetCanvas.Brush.Color := clWindow;
    aTargetCanvas.Pen.Color := $00D0D0D0;
    aTargetCanvas.RoundRect(aRect.Left, aRect.Top, aRect.Right, aRect.Bottom, 6, 6);
    lImageRect := aRect;
    InflateRect(lImageRect, -5, -5);
    ButtonSvgCollection.Draw(aTargetCanvas, lImageRect, aImageIndex, True);
  end;
begin
  if not RepoItemForNode(aNode, lItem) then
    Exit;
  lSavedDc := SaveDC(aTargetCanvas.Handle);
  try
    GetRepoActionRects(lItem, aCellRect, lPullRect, lPushRect, lMoreRect);
    if TVirtualNodeState.vsSelected in aNode.States then
      lTextColor := clHighlightText
    else
      lTextColor := clWindowText;

    lTextRect := Rect(aCellRect.Left + 16, aCellRect.Top + 6, lMoreRect.Left - 8,
      aCellRect.Top + 30);
    if not IsRectEmpty(lPullRect) then
      lTextRect.Right := lPullRect.Left - 8
    else if not IsRectEmpty(lPushRect) then
      lTextRect.Right := lPushRect.Left - 8;
    aTargetCanvas.Brush.Style := bsClear;
    aTargetCanvas.Font.Assign(Font);
    aTargetCanvas.Font.Height := -16;
    aTargetCanvas.Font.Style := [fsBold];
    aTargetCanvas.Font.Color := lTextColor;
    DrawText(aTargetCanvas.Handle, PChar(lItem.DisplayPath), -1, lTextRect,
      DT_END_ELLIPSIS or DT_NOPREFIX or DT_SINGLELINE or DT_VCENTER);

    aTargetCanvas.Font.Assign(Font);
    aTargetCanvas.Font.Height := -13;
    aTargetCanvas.Font.Style := [];
    lBadgeX := aCellRect.Left + 16;
    lBadgeRight := lTextRect.Right;
    if lItem.State = TRepoListItemState.rlisWaiting then
      DrawBadge(rsStatusWaiting, False)
    else begin
      DrawBadge(rsBadgeBranch + lItem.Status.Branch, False);
      if lItem.Status.FetchFailed then
        DrawBadge(rsBadgeFetchFailed, True)
      else if not lItem.Status.HasOrigin then
        DrawBadge(rsBadgeNoOrigin, True)
      else if lItem.Status.Upstream = '' then
        DrawBadge(rsBadgeNoUpstream, True)
      else if lItem.Status.IsOutOfDate then
        DrawBadge(rsBadgeBehind + IntToStr(lItem.Status.Behind), True)
      else if lItem.Status.HasUnpushed then
        DrawBadge(rsBadgeAhead + IntToStr(lItem.Status.Ahead), True)
      else
        DrawBadge(rsBadgeSyncOk, False);
      if lItem.Status.SubmoduleNeedsMainFastForward then
        DrawBadge(rsBadgeSubmoduleNoFastForward + lItem.Status.SubmoduleMainRemoteRef, True);
      if lItem.Status.IsDirty then
      begin
        lDirty := BuildDirtyBadge(lItem.Status.DirtySummary, lHasFiles);
        DrawBadge(lDirty, True);
      end;
    end;

    DrawAction(lPullRect, 1);
    DrawAction(lPushRect, 2);
    aTargetCanvas.Brush.Color := clWindow;
    aTargetCanvas.Pen.Color := $00D0D0D0;
    aTargetCanvas.RoundRect(lMoreRect.Left, lMoreRect.Top, lMoreRect.Right,
      lMoreRect.Bottom, 6, 6);
    aTargetCanvas.Brush.Style := bsClear;
    aTargetCanvas.Font.Assign(Font);
    aTargetCanvas.Font.Style := [fsBold];
    aTargetCanvas.Font.Color := clWindowText;
    aTargetCanvas.TextOut(lMoreRect.Left + 9, lMoreRect.Top + 4, '...');
    aTargetCanvas.Pen.Color := $00ECECEC;
    aTargetCanvas.MoveTo(aCellRect.Left + 16, aCellRect.Bottom - 3);
    aTargetCanvas.LineTo(aCellRect.Right - 12, aCellRect.Bottom - 3);
  finally
    RestoreDC(aTargetCanvas.Handle, lSavedDc);
  end;
end;

procedure TfrmMain.RepoTreeMouseDown(aSender: TObject; aButton: TMouseButton;
  aShift: TShiftState; X, Y: Integer);
var
  lNode: PVirtualNode;
begin
  lNode := RepoTree.GetNodeAt(X, Y);
  if lNode = nil then
    Exit;
  RepoTree.FocusedNode := lNode;
  RepoTree.Selected[lNode] := True;
end;

procedure TfrmMain.RepoTreeMouseUp(aSender: TObject; aButton: TMouseButton;
  aShift: TShiftState; X, Y: Integer);
var
  lNode: PVirtualNode;
  lItem: TRepoListItem;
  lCellRect: TRect;
  lPullRect: TRect;
  lPushRect: TRect;
  lMoreRect: TRect;
  lPoint: TPoint;
begin
  if aButton <> mbLeft then
    Exit;
  lNode := RepoTree.GetNodeAt(X, Y);
  if not RepoItemForNode(lNode, lItem) then
    Exit;
  lCellRect := RepoTree.GetDisplayRect(lNode, 0, False);
  GetRepoActionRects(lItem, lCellRect, lPullRect, lPushRect, lMoreRect);
  lPoint := Point(X, Y);
  if PtInRect(lPullRect, lPoint) then
    ExecuteRepoAction(TRepoAction.raPull, lItem.RepoRoot)
  else if PtInRect(lPushRect, lPoint) then
    ExecuteRepoAction(TRepoAction.raPush, lItem.RepoRoot)
  else if PtInRect(lMoreRect, lPoint) then
    ShowRepoPopup(lItem.RepoRoot, RepoTree.ClientToScreen(Point(lMoreRect.Left, lMoreRect.Bottom)));
end;

procedure TfrmMain.RepoActionsPopup(aSender: TObject);
var
  lRepoRoot: string;
begin
  lRepoRoot := SelectedRepoRoot;
  if lRepoRoot = '' then
  begin
    fPopupRepoRoot := '';
    Exit;
  end;
  PrepareRepoPopup(lRepoRoot);
end;

procedure TfrmMain.RepoMenuClick(Sender: TObject);
var
  lAction: TRepoAction;
  lError: string;
begin
  if fPopupRepoRoot = '' then
    Exit;
  if Sender = miRepoTortoiseCommit then
  begin
    if not TTortoiseGit.TryLaunch(fTortoiseGitExe, TTortoiseGitCommand.tgcCommit,
      fPopupRepoRoot, lError) then
      MessageDlg(lError, mtError, [mbOK], 0);
    Exit;
  end else if Sender = miRepoTortoiseSync then
  begin
    if not TTortoiseGit.TryLaunch(fTortoiseGitExe, TTortoiseGitCommand.tgcSync,
      fPopupRepoRoot, lError) then
      MessageDlg(lError, mtError, [mbOK], 0);
    Exit;
  end else if Sender = miRepoCommit then
    lAction := TRepoAction.raCommit
  else if Sender = miRepoFetch then
    lAction := TRepoAction.raFetch
  else if Sender = miRepoFixSubmoduleMain then
    lAction := TRepoAction.raFixSubmoduleMain
  else if Sender = miRepoRescan then
    lAction := TRepoAction.raRescan
  else if Sender = miRepoOpenFolder then
    lAction := TRepoAction.raOpenFolder
  else
    Exit;
  ExecuteRepoAction(lAction, fPopupRepoRoot);
end;

procedure TfrmMain.ExecuteRepoAction(const aAction: TRepoAction; const aRepoRoot: string);
var
  lMsg: string;
  lStatus: TRepoStatus;
  lBranchName: string;
  lSlashPos: Integer;
begin
  if aAction = TRepoAction.raCommit then
  begin
    lMsg := '';
    if not InputQuery(rsCommitTitle, rsCommitPrompt, lMsg) then
      Exit;
    RunRepoAction(aAction, aRepoRoot, lMsg);
    Exit;
  end;

  if aAction = TRepoAction.raOpenFolder then
  begin
    ShellExecute(Handle, 'open', PChar(aRepoRoot), nil, nil, SW_SHOWNORMAL);
    Exit;
  end;

  if aAction = TRepoAction.raFixSubmoduleMain then
  begin
    if not fRepoStatusMap.TryGetValue(aRepoRoot, lStatus) then
      Exit;
    if lStatus.SubmoduleMainRemoteRef = '' then
    begin
      MessageDlg(rsFixSubmoduleMissingRef, mtWarning, [mbOK], 0);
      Exit;
    end;
    lSlashPos := lStatus.SubmoduleMainRemoteRef.IndexOf('/');
    if lSlashPos < 0 then
      lBranchName := lStatus.SubmoduleMainRemoteRef
    else
      lBranchName := lStatus.SubmoduleMainRemoteRef.Substring(lSlashPos + 1);
    if MessageDlg(Format(rsFixSubmoduleConfirm, [lStatus.SubmoduleMainRemoteRef, lBranchName,
      lStatus.SubmoduleMainRemoteRef]), mtWarning, [mbYes, mbNo], 0) <> mrYes then
      Exit;
    RunRepoAction(aAction, aRepoRoot, lStatus.SubmoduleMainRemoteRef);
    Exit;
  end;

  RunRepoAction(aAction, aRepoRoot, '');
end;

procedure TfrmMain.RunRepoAction(const aAction: TRepoAction; const aRepoRoot: string; const aMessage: string);
var
  lActionName: string;
  lThread: TThread;
  lMsg: string;
  lOk: Boolean;
  lErr: string;
  lEvent: TUiEvent;
  lMatched: TArray<string>;
  lExisting: TRepoStatus;
  lParentExisting: TRepoStatus;
  lParentRepoRoot: string;
  lParentMatched: TArray<string>;
  lFetchRemote: string;
  lSlashPos: integer;
begin
  if fShuttingDown then
    Exit;
  CleanupFinishedActionThreads;
  case aAction of
    TRepoAction.raPull: lActionName := rsPull;
    TRepoAction.raCommit: lActionName := rsCommit;
    TRepoAction.raPush: lActionName := rsPush;
    TRepoAction.raFetch: lActionName := rsFetch;
    TRepoAction.raFixSubmoduleMain: lActionName := rsFixSubmoduleMain;
    TRepoAction.raRescan: lActionName := rsRescanAction;
  else
    lActionName := rsOpenFolder;
  end;

  lMatched := [];
  lParentRepoRoot := '';
  lParentMatched := [];
  lFetchRemote := '';
  if fRepoStatusMap.TryGetValue(aRepoRoot, lExisting) then
  begin
    lMatched := lExisting.MatchedFolders;
    if (aAction in [TRepoAction.raPull, TRepoAction.raPush]) and lExisting.IsSubmodule and
      (lExisting.SuperprojectRoot <> '') and
      fRepoStatusMap.TryGetValue(lExisting.SuperprojectRoot, lParentExisting) then
    begin
      lParentRepoRoot := lParentExisting.RepoRoot;
      lParentMatched := lParentExisting.MatchedFolders;
    end;
    if lExisting.Upstream <> '' then
    begin
      lSlashPos := lExisting.Upstream.IndexOf('/');
      if lSlashPos > 0 then
        lFetchRemote := lExisting.Upstream.Substring(0, lSlashPos);
    end;
  end;
  if lFetchRemote = '' then
    lFetchRemote := 'origin';

  BeginActionBusy;
  try
    lThread := TThread.CreateAnonymousThread(
      procedure
      var
        lStatus: TRepoStatus;
        lStatusErr: string;
        lStatusOk: Boolean;
        lParentStatus: TRepoStatus;
        lParentStatusErr: string;
        lParentStatusOk: Boolean;
        lScanner: TRepoScanner;
      begin
        try
          lErr := '';
          lOk := False;
          case aAction of
            TRepoAction.raPull: lOk := fGit.TryPull(aRepoRoot, lErr);
            TRepoAction.raCommit: lOk := fGit.TryCommit(aRepoRoot, aMessage, lErr);
            TRepoAction.raPush: lOk := fGit.TryPush(aRepoRoot, lErr);
            TRepoAction.raFetch: lOk := fGit.TryFetchRemote(aRepoRoot, lFetchRemote, 60000, lErr);
            TRepoAction.raFixSubmoduleMain: lOk := fGit.TryFixSubmoduleFastForwardToMain(aRepoRoot, aMessage, lErr);
            TRepoAction.raRescan: lOk := True;
          end;

          if lOk then
            lMsg := Format('%s %s: %s', [cLogAction, lActionName, cLogActionOk])
          else
            lMsg := Format('%s %s: %s - %s', [cLogAction, lActionName, cLogActionFailed, lErr]);
        except
          on E: Exception do
          begin
            lErr := E.Message;
            lOk := False;
            lMsg := Format('%s %s: %s - %s', [cLogAction, lActionName, cLogActionFailed, E.Message]);
          end;
        end;

        lStatusOk := False;
        lStatusErr := '';
        lParentStatusOk := False;
        lParentStatusErr := '';
        try
          lScanner := TRepoScanner.Create(fGit);
          try
            try
              lStatusOk := lScanner.TryRefreshRepoStatus(fSettings, aRepoRoot, lMatched, lStatus, lStatusErr);
            except
              on E: Exception do
                lStatusErr := E.Message;
            end;
            if lParentRepoRoot <> '' then
            begin
              try
                lParentStatusOk := lScanner.TryRefreshRepoStatus(fSettings, lParentRepoRoot,
                  lParentMatched, lParentStatus, lParentStatusErr);
              except
                on E: Exception do
                  lParentStatusErr := E.Message;
              end;
            end;
          finally
            lScanner.Free;
          end;
        except
          on E: Exception do
          begin
            if lStatusErr = '' then
              lStatusErr := E.Message;
            if lParentStatusErr = '' then
              lParentStatusErr := E.Message;
          end;
        end;

        if aAction = TRepoAction.raRescan then
        begin
          lOk := lStatusOk;
          lErr := lStatusErr;
          if lOk then
            lMsg := Format('%s %s: %s', [cLogAction, lActionName, cLogActionOk])
          else
            lMsg := Format('%s %s: %s - %s', [cLogAction, lActionName, cLogActionFailed, lErr]);
        end;

        if (lParentRepoRoot <> '') and (not lParentStatusOk) then
          lMsg := lMsg + ' | ' + Format(cLogParentRefreshFailed, [lParentStatusErr]);

        if fShuttingDown then
          Exit;

        lEvent := Default(TUiEvent);
        lEvent.Kind := TUiEventKind.uekActionResult;
        lEvent.Text := lMsg;
        lEvent.ActionTag := Ord(aAction);
        lEvent.ActionSucceeded := lOk;
        lEvent.ActionError := lErr;
        if (not lOk) and (aAction = TRepoAction.raPull) and TGitClient.IsPullConflictError(lErr) then
          lEvent.AlertText := Format(rsPullConflictAlert, [aRepoRoot, lErr]);
        if lStatusOk then
          lEvent.RepoStatus := lStatus;
        if lParentStatusOk then
          lEvent.RelatedRepoStatus := lParentStatus;
        fQueue.Enqueue(lEvent);
      end
    );
  except
    on Exception do
    begin
      EndActionBusy;
      raise;
    end;
  end;
  lThread.FreeOnTerminate := False;
  AddActionThread(lThread);
  lThread.Start;
end;

procedure TfrmMain.btnScanClick(Sender: TObject);
var
  lErr: string;
begin
  if not ReadSettingsFromUi(lErr) then
  begin
    MessageDlg(rsInvalidInput + lErr, mtWarning, [mbOK], 0);
    Exit;
  end;
  fSettings.Save;
  StartScan;
end;

procedure TfrmMain.btnCancelClick(Sender: TObject);
begin
  if fCancelToken <> nil then
  begin
    fCancelToken.Cancel;
  end;
  QueueLog(cLogScanCancelled);
end;

procedure TfrmMain.btnPullVisibleClick(Sender: TObject);
begin
  RunBulkAction(TRepoAction.raPull);
end;

procedure TfrmMain.btnPushVisibleClick(Sender: TObject);
begin
  RunBulkAction(TRepoAction.raPush);
end;

procedure TfrmMain.btnEditIgnoreDirsClick(Sender: TObject);
var
  lPath: string;
begin
  lPath := ResolveIgnoreDirsPath;
  EditIgnoreDirsFile(lPath);
end;

procedure TfrmMain.btnBrowseStartClick(Sender: TObject);
var
  lPaths: TArray<string>;
begin
  if TfrmScanPathsDialog.Execute(Self, fSettings.ScanPaths, lPaths) then
  begin
    fSettings.ScanPaths := lPaths;
    fSettings.StartPath := lPaths[0];
    UpdateScanPathsDisplay;
  end;
end;

procedure TfrmMain.btnSettingsClick(Sender: TObject);
begin
  pnlSettingsDrawer.Visible := not pnlSettingsDrawer.Visible;
  if pnlSettingsDrawer.Visible then
    pnlSettingsDrawer.BringToFront;
end;

procedure TfrmMain.btnShowLogClick(Sender: TObject);
begin
  pnlLogDrawer.Visible := not pnlLogDrawer.Visible;
  if pnlLogDrawer.Visible then
    btnShowLog.Caption := rsHideLog
  else
    btnShowLog.Caption := rsShowLog;
end;

procedure TfrmMain.cboStatusFilterChange(Sender: TObject);
begin
  if (cboStatusFilter.ItemIndex >= 0) and (cboStatusFilter.ItemIndex <= Ord(High(TRepoFilter))) then
    fStatusFilter := TRepoFilter(cboStatusFilter.ItemIndex)
  else
    fStatusFilter := TRepoFilter.rfAttention;
  ApplyStatusFilter;
end;

procedure TfrmMain.pnlStatusDblClick(Sender: TObject);
begin
  CopyStatusToClipboard;
end;


procedure TfrmMain.tmrUiTimer(Sender: TObject);
var
  lMetrics: string;
  lResult: TUiEventPumpResult;
  lStopwatch: TStopwatch;
begin
  lStopwatch := TStopwatch.StartNew;
  lResult := TUiEventPump.Process(fQueue, fScanGeneration, cMaxUiEventsPerTick,
    cMaxUiMillisecondsPerTick, HandleUiEvent);
  if fRepoViewDirty and ((not lResult.HasMore) or
    (GetTickCount64 - fLastRepoViewFlushTick >= cRepoViewFlushInterval)) then
    FlushRepoView;
  if lStopwatch.ElapsedMilliseconds > fMaxUiBatchMilliseconds then
    fMaxUiBatchMilliseconds := lStopwatch.ElapsedMilliseconds;
  if lResult.HasMore then
    tmrUi.Interval := cBusyUiTimerInterval
  else
    tmrUi.Interval := cIdleUiTimerInterval;
  if fUiMetricsPending and (fScanThread = nil) and not lResult.HasMore then
  begin
    fUiMetricsPending := False;
    lMetrics := Format(cLogUiMetrics, [fQueue.PeakCount, fMaxUiBatchMilliseconds]);
    memLog.Lines.Add(lMetrics);
    maxLog.Info(lMetrics);
  end;
  CleanupFinishedActionThreads;
end;

procedure TfrmMain.AddActionThread(const aThread: TThread);
begin
  fActionLock.Enter;
  try
    fActionThreads.Add(aThread);
  finally
    fActionLock.Leave;
  end;
end;

procedure TfrmMain.CleanupFinishedActionThreads;
var
  g: TGarbos;
  lToFree: TList<TThread>;
  lThread: TThread;
  i: Integer;
  lFreedCount: Integer;
begin
  GC(lToFree, TList<TThread>.Create, g);
  lFreedCount := 0;
  fActionLock.Enter;
  try
    for i := fActionThreads.Count - 1 downto 0 do
    begin
      lThread := fActionThreads[i];
      if lThread.Finished then
      begin
        lToFree.Add(lThread);
        fActionThreads.Delete(i);
        Inc(lFreedCount);
      end;
    end;
  finally
    fActionLock.Leave;
  end;

  for lThread in lToFree do
    lThread.Free;
  EndActionBusy(lFreedCount);
end;

procedure TfrmMain.WaitForActionThreads;
var
  g: TGarbos;
  lThreads: TList<TThread>;
  lThread: TThread;
  i: Integer;
  lCount: Integer;
begin
  GC(lThreads, TList<TThread>.Create, g);
  fActionLock.Enter;
  try
    for i := 0 to fActionThreads.Count - 1 do
      lThreads.Add(fActionThreads[i]);
    fActionThreads.Clear;
  finally
    fActionLock.Leave;
  end;

  lCount := lThreads.Count;
  for lThread in lThreads do
  begin
    lThread.WaitFor;
    lThread.Free;
  end;
  EndActionBusy(lCount);
end;

end.
