unit UMainForm;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.StrUtils, System.SyncObjs,
  System.SysUtils, System.Types,
  Winapi.ShellAPI, Winapi.Windows,
  Vcl.Clipbrd, Vcl.ComCtrls, Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics,
  Vcl.Menus, Vcl.StdCtrls,
  AutoFree, AutoHourGlass, CancelToken, MaxLogic.ApplicationMessageManager, MaxLogic.Logger, maxLogic.ioutils,
  UAppSettings, UGitClient, UModels, URepoScanner, UUiEventQueue;

type
  {$SCOPEDENUMS ON}
  TRepoAction = (raPull, raCommit, raPush, raFetch, raOpenFolder);
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
    sbRepos: TScrollBox;
    fpRepos: TFlowPanel;
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
    miRepoOpenFolder: TMenuItem;
    pbProgress: TProgressBar;
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
    procedure sbReposResize(Sender: TObject);
    procedure RepoMenuClick(Sender: TObject);
    procedure tmrUiTimer(Sender: TObject);
  private
    fSettings: TAppSettings;
    fGit: TGitClient;
    fScanner: TRepoScanner;
    fQueue: TUiEventQueue;
    fScanThread: TThread;
    fCancelToken: iCancelToken;
    fButtonRepoMap: TDictionary<TObject, string>;
    fActionThreads: TList<TThread>;
    fActionLock: TCriticalSection;
    fActionBusyCount: Integer;
    fActionHourglass: IInterface;
    fShuttingDown: Boolean;
    fPopupRepoRoot: string;
    fRepoStatusMap: TDictionary<string, TRepoStatus>;
    fStatusFilter: TRepoFilter;
    fRedirectMouseWheel: TAppMessagehandlerRedirectMouseWheel;
    procedure LoadSettingsToUi;
    function ReadSettingsFromUi(out aError: string): Boolean;
    function EditIgnoreDirsFile(const aPath: string): Boolean;
    function ResolveIgnoreDirsPath: string;
    function EllipsizeMiddle(const aText: string; const aMax: Integer): string;
    function EllipsizeMiddleToWidth(const aText: string; const aMaxWidth: Integer; const aCanvas: TCanvas): string;
    function GetRelativeRepoPath(const aRepoRoot: string): string;
    function BuildDirtyBadge(const aDirtySummary: string; out aHasFiles: Boolean): string;
    function RepoMatchesFilter(const aStatus: TRepoStatus): Boolean;
    procedure UpdateStatusFilterItems;
    procedure StartScan;
    procedure SetScanningState(const aScanning: Boolean);
    procedure BeginActionBusy;
    procedure EndActionBusy(const aCount: Integer = 1);
    procedure ClearRepoPanels;
    procedure AddRepoPanel(const aStatus: TRepoStatus);
    procedure BuildRepoCard(const aStatus: TRepoStatus; const aCard: TPanel);
    procedure UpdateRepoPanel(const aStatus: TRepoStatus);
    function TryFindRepoCard(const aRepoRoot: string; out aCard: TPanel; out aIndex: Integer): Boolean;
    function FindRepoPathLabel(const aCard: TPanel): TStaticText;
    procedure UpdateRepoPathLabel(const aCard: TPanel);
    procedure RemoveButtonsFromMap(const aParent: TWinControl);
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
    procedure RepoActionClick(Sender: TObject);
    procedure RepoMoreClick(Sender: TObject);
    procedure ExecuteRepoAction(const aAction: TRepoAction; const aRepoRoot: string);
    procedure UpdateRepoCardWidths;
    procedure UpdateStatusText(const aText: string);
    procedure RunRepoAction(const aAction: TRepoAction; const aRepoRoot: string; const aMessage: string);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

resourcestring
  rsFormCaption = 'Scan Git Repos';
  rsSettingsHeader = 'Settings';
  rsStartPath = 'Scan Directory';
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

const
  cRepoPathLabelTag = 901;
  rsTargetName = 'Search Filter';
  rsScan = 'Scan';
  rsCancel = 'Cancel';
  rsSettings = 'Settings';
  rsShowLog = 'Show log';
  rsHideLog = 'Hide log';
  rsPull = 'Pull';
  rsCommit = 'Commit';
  rsPush = 'Push';
  rsFetch = 'Fetch';
  rsOpenFolder = 'Open folder';
  rsCommitPrompt = 'Commit message:';
  rsCommitTitle = 'Commit';
  rsInvalidInput = 'Invalid input: ';
  rsOk = 'OK';
  rsErrStartPathRequired = 'Scan directory is required';
  rsErrStartPathMissing = 'Scan directory does not exist';
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
  rsStatusReady = 'Ready';
  rsStatusScanning = 'Scanning...';

const
  cLogScanStarted = 'Scan started.';
  cLogScanCancelled = 'Cancel requested.';
  cLogAction = 'Action';
  cLogActionOk = 'OK';
  cLogActionFailed = 'FAILED';
  cIgnoreFileName = '.ignoredirectory';

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  fSettings := TAppSettings.Create;
  fSettings.Load;

  fGit := TGitClient.Create;
  fScanner := TRepoScanner.Create(fGit);
  fQueue := TUiEventQueue.Create;
  fButtonRepoMap := TDictionary<TObject, string>.Create;
  fRepoStatusMap := TDictionary<string, TRepoStatus>.Create;
  fActionThreads := TList<TThread>.Create;
  fActionLock := TCriticalSection.Create;
  fShuttingDown := False;

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
  btnSettings.Caption := rsSettings;
  btnShowLog.Caption := rsShowLog;
  btnPullVisible.Caption := rsPullAll;
  btnPushVisible.Caption := rsPushAll;

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
  fButtonRepoMap.Free;
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
  edtStartPath.Text := fSettings.StartPath;
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

function TfrmMain.ReadSettingsFromUi(out aError: string): Boolean;
var
  g: TGarbos;
  lValue: string;
  lNum: Integer;
  i: Integer;
  lHistory: TList<string>;
  lFound: Boolean;
  lItem: string;
  lRepoNameHistory: TArray<string>;
begin
  aError := '';
  Result := False;

  lValue := Trim(edtStartPath.Text);
  if lValue = '' then
  begin
    aError := rsErrStartPathRequired;
    Exit(False);
  end;
  if not DirectoryExists(lValue) then
  begin
    aError := rsErrStartPathMissing;
    Exit(False);
  end;
  fSettings.StartPath := lValue;

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
    fSettings.TargetRepoName := 'maxlogicfoundation';
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

function TfrmMain.EllipsizeMiddle(const aText: string; const aMax: Integer): string;
var
  lKeep: Integer;
  lLeft: Integer;
  lRight: Integer;
begin
  Result := aText;
  if (aMax <= 0) or (Length(aText) <= aMax) then
    Exit;
  if aMax <= 3 then
  begin
    Result := Copy(aText, 1, aMax);
    Exit;
  end;
  lKeep := aMax - 3;
  lLeft := lKeep div 2;
  lRight := lKeep - lLeft;
  Result := Copy(aText, 1, lLeft) + '...' + Copy(aText, Length(aText) - lRight + 1, lRight);
end;

function TfrmMain.EllipsizeMiddleToWidth(const aText: string; const aMaxWidth: Integer; const aCanvas: TCanvas): string;
var
  lLow: Integer;
  lHigh: Integer;
  lMid: Integer;
  lCandidate: string;
begin
  Result := aText;
  if (aCanvas = nil) or (aMaxWidth <= 0) then
    Exit;
  if aCanvas.TextWidth(aText) <= aMaxWidth then
    Exit;
  lLow := 1;
  lHigh := Length(aText);
  while lLow <= lHigh do
  begin
    lMid := (lLow + lHigh) div 2;
    lCandidate := EllipsizeMiddle(aText, lMid);
    if aCanvas.TextWidth(lCandidate) <= aMaxWidth then
    begin
      Result := lCandidate;
      lLow := lMid + 1;
    end else begin
      lHigh := lMid - 1;
    end;
  end;
end;

function TfrmMain.GetRelativeRepoPath(const aRepoRoot: string): string;
var
  lBase: string;
  lRelative: string;
begin
  lBase := Trim(fSettings.StartPath);
  if lBase <> '' then
  begin
    lBase := IncludeTrailingPathDelimiter(lBase);
    lRelative := ExtractRelativePath(lBase, aRepoRoot);
    if (lRelative <> '') and (Copy(lRelative, 1, 2) <> '..') then
    begin
      Result := ExcludeTrailingPathDelimiter(lRelative);
      Exit;
    end;
  end;
  Result := ExtractFileName(aRepoRoot);
  if Result = '' then
    Result := aRepoRoot;
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

function TfrmMain.RepoMatchesFilter(const aStatus: TRepoStatus): Boolean;
begin
  case fStatusFilter of
    TRepoFilter.rfAttention:
      Result := aStatus.HasProblem;
    TRepoFilter.rfAll:
      Result := True;
    TRepoFilter.rfDirty:
      Result := aStatus.IsDirty;
    TRepoFilter.rfBehind:
      Result := aStatus.IsOutOfDate;
    TRepoFilter.rfDetached:
      Result := SameText(aStatus.Branch, rsBranchDetached);
    TRepoFilter.rfClean:
      Result := not aStatus.HasProblem;
  else
    Result := True;
  end;
end;

procedure TfrmMain.UpdateStatusText(const aText: string);
begin
  stsMain.SimpleText := aText;
end;

procedure TfrmMain.ApplyStatusFilter;
var
  i: Integer;
  lControl: TControl;
  lCard: TPanel;
  lStatus: TRepoStatus;
begin
  if fpRepos = nil then
    Exit;
  for i := 0 to fpRepos.ControlCount - 1 do
  begin
    lControl := fpRepos.Controls[i];
    if not (lControl is TPanel) then
      Continue;
    lCard := TPanel(lControl);
    if fRepoStatusMap.TryGetValue(lCard.Hint, lStatus) then
      lCard.Visible := RepoMatchesFilter(lStatus)
    else
      lCard.Visible := True;
  end;
  UpdateRepoCardWidths;
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
  lStatus: TRepoStatus;
  lIndex: Integer;
begin
  lAttention := 0;
  lAll := 0;
  lDirty := 0;
  lBehind := 0;
  lDetached := 0;
  lClean := 0;
  for lStatus in fRepoStatusMap.Values do
  begin
    Inc(lAll);
    if lStatus.HasProblem then
      Inc(lAttention)
    else
      Inc(lClean);
    if lStatus.IsDirty then
      Inc(lDirty);
    if lStatus.IsOutOfDate then
      Inc(lBehind);
    if SameText(lStatus.Branch, rsBranchDetached) then
      Inc(lDetached);
  end;

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
  lControl: TControl;
  lCard: TPanel;
  lStatus: TRepoStatus;
  lHasPull: Boolean;
  lHasPush: Boolean;
begin
  lHasPull := False;
  lHasPush := False;
  if fpRepos <> nil then
  begin
    for i := 0 to fpRepos.ControlCount - 1 do
    begin
      lControl := fpRepos.Controls[i];
      if not (lControl is TPanel) then
        Continue;
      lCard := TPanel(lControl);
      if not lCard.Visible then
        Continue;
      if not fRepoStatusMap.TryGetValue(lCard.Hint, lStatus) then
        Continue;
      if lStatus.IsOutOfDate then
        lHasPull := True;
      if lStatus.IsDirty then
        lHasPush := True;
      if lHasPull and lHasPush then
        Break;
    end;
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
  lControl: TControl;
  lCard: TPanel;
  lStatus: TRepoStatus;
begin
  if fpRepos = nil then
    Exit;
  for i := 0 to fpRepos.ControlCount - 1 do
  begin
    lControl := fpRepos.Controls[i];
    if not (lControl is TPanel) then
      Continue;
    lCard := TPanel(lControl);
    if not lCard.Visible then
      Continue;
    if not fRepoStatusMap.TryGetValue(lCard.Hint, lStatus) then
      Continue;
    case aAction of
      TRepoAction.raPull:
        if not lStatus.IsOutOfDate then
          Continue;
      TRepoAction.raPush:
        if not lStatus.IsDirty then
          Continue;
    else
      Continue;
    end;
    ExecuteRepoAction(aAction, lStatus.RepoRoot);
  end;
end;

function TfrmMain.EditIgnoreDirsFile(const aPath: string): Boolean;
var
  g: TGarbos;
  lForm: TForm;
  lMemo: TMemo;
  lPanel: TPanel;
  lOk: TButton;
  lCancel: TButton;
  lFolder: string;
  i: Integer;
begin
  Result := False;

  GC(lForm, TForm.CreateNew(nil), g);
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
  if aScanning then
  begin
    btnScan.Caption := rsCancel;
    btnScan.OnClick := btnCancelClick;
  end else begin
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
var
  i: Integer;
begin
  for i := fpRepos.ControlCount - 1 downto 0 do
    fpRepos.Controls[i].Free;
  fButtonRepoMap.Clear;
  fRepoStatusMap.Clear;
  UpdateBulkActionButtons;
  UpdateStatusFilterItems;
end;

procedure TfrmMain.AddRepoPanel(const aStatus: TRepoStatus);
begin
  BuildRepoCard(aStatus, TPanel.Create(fpRepos));
end;

procedure TfrmMain.BuildRepoCard(const aStatus: TRepoStatus; const aCard: TPanel);
var
  lInfoPanel: TPanel;
  lActionsPanel: TFlowPanel;
  lBadges: TFlowPanel;
  lName: TStaticText;
  lBtn: TButton;
  lRepoLabel: string;
  lDirtyBadge: string;
  lHasDirtyFiles: Boolean;
  lBadge: TStaticText;
  lActionCount: Integer;

  procedure AddBadge(const aCaption: string; const aMuted: Boolean);
  begin
    lBadge := TStaticText.Create(lBadges);
    lBadge.Parent := lBadges;
    lBadge.AlignWithMargins := True;
    lBadge.Margins.Right := 6;
    lBadge.AutoSize := True;
    lBadge.Caption := '[' + aCaption + ']';
    lBadge.TabStop := False;
    if aMuted then
      lBadge.Font.Color := clGrayText;
  end;
begin
  if aCard = nil then
    Exit;
  if aCard.Parent <> fpRepos then
    aCard.Parent := fpRepos;
  aCard.AlignWithMargins := True;
  aCard.Margins.SetBounds(0, 0, 0, 10);
  aCard.Align := alTop;
  aCard.Height := 84;
  aCard.BevelOuter := bvNone;
  aCard.Color := clWindow;
  aCard.ParentBackground := False;
  aCard.Padding.Left := 12;
  aCard.Padding.Top := 8;
  aCard.Padding.Right := 12;
  aCard.Padding.Bottom := 8;
  aCard.Hint := aStatus.RepoRoot;
  aCard.ShowHint := False;

  lRepoLabel := GetRelativeRepoPath(aStatus.RepoRoot);
  lActionsPanel := TFlowPanel.Create(aCard);
  lActionsPanel.Parent := aCard;
  lActionsPanel.Align := alRight;
  lActionsPanel.Width := 210;
  lActionsPanel.BevelOuter := bvNone;
  lActionsPanel.Color := clWindow;
  lActionsPanel.ParentBackground := False;
  lActionsPanel.Padding.Top := 14;
  lActionsPanel.AutoWrap := False;
  lActionsPanel.FlowStyle := fsLeftRightTopBottom;

  lActionCount := 0;
  if aStatus.IsOutOfDate then
  begin
    lBtn := TButton.Create(lActionsPanel);
    lBtn.Parent := lActionsPanel;
    lBtn.Caption := rsPull;
    lBtn.Width := 72;
    lBtn.Height := 28;
    lBtn.Tag := Ord(TRepoAction.raPull);
    lBtn.Hint := 'Pull changes';
    lBtn.ShowHint := True;
    lBtn.OnClick := RepoActionClick;
    fButtonRepoMap.Add(lBtn, aStatus.RepoRoot);
    Inc(lActionCount);
  end;

  if aStatus.IsDirty then
  begin
    lBtn := TButton.Create(lActionsPanel);
    lBtn.Parent := lActionsPanel;
    lBtn.Caption := rsPush;
    lBtn.Width := 72;
    lBtn.Height := 28;
    lBtn.Tag := Ord(TRepoAction.raPush);
    lBtn.Hint := 'Push changes';
    lBtn.ShowHint := True;
    lBtn.OnClick := RepoActionClick;
    fButtonRepoMap.Add(lBtn, aStatus.RepoRoot);
    Inc(lActionCount);
  end;

  lBtn := TButton.Create(lActionsPanel);
  lBtn.Parent := lActionsPanel;
  lBtn.Caption := '...';
  lBtn.Width := 32;
  lBtn.Height := 28;
  lBtn.Hint := 'More actions';
  lBtn.ShowHint := True;
  lBtn.OnClick := RepoMoreClick;
  fButtonRepoMap.Add(lBtn, aStatus.RepoRoot);
  Inc(lActionCount);

  lActionsPanel.Width := (lActionCount * 80) + 10;

  lInfoPanel := TPanel.Create(aCard);
  lInfoPanel.Parent := aCard;
  lInfoPanel.Align := alClient;
  lInfoPanel.BevelOuter := bvNone;
  lInfoPanel.Color := clWindow;
  lInfoPanel.ParentBackground := False;

  lName := TStaticText.Create(lInfoPanel);
  lName.Parent := lInfoPanel;
  lName.AlignWithMargins := True;
  lName.Margins.Bottom := 2;
  lName.Align := alTop;
  lName.AutoSize := False;
  lName.Height := 22;
  lName.Caption := lRepoLabel;
  lName.Tag := cRepoPathLabelTag;
  lName.Font.Style := [fsBold];
  lName.Font.Height := -16;
  lName.ParentFont := False;

  lBadges := TFlowPanel.Create(lInfoPanel);
  lBadges.Parent := lInfoPanel;
  lBadges.Top:= lName.Top + lName.Height; // ensure the Badges are show below the name of the repo
  lBadges.Align := alTop;
  lBadges.BevelOuter := bvNone;
  lBadges.AutoSize := True;
  lBadges.AutoWrap := False;
  lBadges.FlowStyle := fsLeftRightTopBottom;
  lBadges.Color := clWindow;
  lBadges.ParentBackground := False;

  AddBadge(rsBadgeBranch + aStatus.Branch, True);
  if aStatus.FetchFailed then
    AddBadge(rsBadgeFetchFailed, False)
  else if not aStatus.HasOrigin then
    AddBadge(rsBadgeNoOrigin, False)
  else if aStatus.Upstream = '' then
    AddBadge(rsBadgeNoUpstream, False)
  else if aStatus.IsOutOfDate then
    AddBadge(rsBadgeBehind + IntToStr(aStatus.Behind), False)
  else if aStatus.HasUnpushed then
    AddBadge(rsBadgeAhead + IntToStr(aStatus.Ahead), False)
  else
    AddBadge(rsBadgeSyncOk, True);

  if aStatus.IsDirty then
  begin
    lDirtyBadge := BuildDirtyBadge(aStatus.DirtySummary, lHasDirtyFiles);
    AddBadge(lDirtyBadge, False);
  end;

  fRepoStatusMap.AddOrSetValue(aStatus.RepoRoot, aStatus);
  aCard.Visible := RepoMatchesFilter(aStatus);
  UpdateRepoCardWidths;
  UpdateBulkActionButtons;
  UpdateStatusFilterItems;
end;

procedure TfrmMain.UpdateRepoPanel(const aStatus: TRepoStatus);
var
  lCard: TPanel;
  lIndex: Integer;
begin
  if TryFindRepoCard(aStatus.RepoRoot, lCard, lIndex) then
  begin
    RemoveButtonsFromMap(lCard);
    while lCard.ControlCount > 0 do
      lCard.Controls[0].Free;
    BuildRepoCard(aStatus, lCard);
  end else begin
    AddRepoPanel(aStatus);
  end;
end;

function TfrmMain.TryFindRepoCard(const aRepoRoot: string; out aCard: TPanel; out aIndex: Integer): Boolean;
var
  i: Integer;
  lControl: TControl;
begin
  Result := False;
  aCard := nil;
  aIndex := -1;
  if fpRepos = nil then
    Exit;
  for i := 0 to fpRepos.ControlCount - 1 do
  begin
    lControl := fpRepos.Controls[i];
    if (lControl is TPanel) and (TPanel(lControl).Hint = aRepoRoot) then
    begin
      aCard := TPanel(lControl);
      aIndex := i;
      Exit(True);
    end;
  end;
end;

function TfrmMain.FindRepoPathLabel(const aCard: TPanel): TStaticText;
  function FindInParent(const aParent: TWinControl): TStaticText;
  var
    i: Integer;
    lChild: TControl;
  begin
    Result := nil;
    for i := 0 to aParent.ControlCount - 1 do
    begin
      lChild := aParent.Controls[i];
      if (lChild is TStaticText) and (lChild.Tag = cRepoPathLabelTag) then
        Exit(TStaticText(lChild));
      if lChild is TWinControl then
      begin
        Result := FindInParent(TWinControl(lChild));
        if Result <> nil then
          Exit;
      end;
    end;
  end;
begin
  Result := nil;
  if aCard = nil then
    Exit;
  Result := FindInParent(aCard);
end;

procedure TfrmMain.UpdateRepoPathLabel(const aCard: TPanel);
var
  lName: TStaticText;
  lText: string;
  lMaxWidth: Integer;
  lCanvas: TControlCanvas;
  g: TGarbos;
begin
  lName := FindRepoPathLabel(aCard);
  if lName = nil then
    Exit;
  lText := GetRelativeRepoPath(aCard.Hint);
  GC(lCanvas, TControlCanvas.Create, g);
  lCanvas.Control := lName;
  lCanvas.Font.Assign(lName.Font);
  if lName.Parent <> nil then
    lMaxWidth := TWinControl(lName.Parent).ClientWidth - 4
  else
    lMaxWidth := lName.Width - 4;
  if lMaxWidth < 0 then
    lMaxWidth := 0;
  lName.Caption := EllipsizeMiddleToWidth(lText, lMaxWidth, lCanvas);
end;

procedure TfrmMain.RemoveButtonsFromMap(const aParent: TWinControl);
var
  i: Integer;
  lControl: TControl;
begin
  if aParent = nil then
    Exit;
  for i := aParent.ControlCount - 1 downto 0 do
  begin
    lControl := aParent.Controls[i];
    if lControl is TButton then
      fButtonRepoMap.Remove(lControl);
    if lControl is TWinControl then
      RemoveButtonsFromMap(TWinControl(lControl));
  end;
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
  lEvent.Text := aText;
  fQueue.Enqueue(lEvent);
end;

procedure TfrmMain.StartScan;
var
  lEvent: TUiEvent;
begin
  if fScanThread <> nil then
    Exit;

  ClearRepoPanels;
  memLog.Clear;
  UpdateStatusText(rsStatusScanning);
  QueueLog(cLogScanStarted);

  fCancelToken := TCancelToken.Create;
  SetScanningState(True);

  lEvent := Default(TUiEvent);
  lEvent.Kind := TUiEventKind.uekClearResults;
  fQueue.Enqueue(lEvent);

  fScanThread := TThread.CreateAnonymousThread(
    procedure
    var
      lErrEvent: TUiEvent;
    begin
      try
        fScanner.ExecuteScan(fSettings, fQueue, fCancelToken);
      except
        on E: Exception do
        begin
          lErrEvent := Default(TUiEvent);
          lErrEvent.Kind := TUiEventKind.uekLog;
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

procedure TfrmMain.RepoActionClick(Sender: TObject);
var
  lBtn: TButton;
  lRepo: string;
  lAction: TRepoAction;
begin
  if not (Sender is TButton) then
    Exit;
  lBtn := TButton(Sender);
  if not fButtonRepoMap.TryGetValue(lBtn, lRepo) then
    Exit;

  lAction := TRepoAction(lBtn.Tag);
  ExecuteRepoAction(lAction, lRepo);
end;

procedure TfrmMain.RepoMoreClick(Sender: TObject);
var
  lBtn: TButton;
  lRepo: string;
  lPt: TPoint;
  lStatus: TRepoStatus;
begin
  if not (Sender is TButton) then
    Exit;
  lBtn := TButton(Sender);
  if not fButtonRepoMap.TryGetValue(lBtn, lRepo) then
    Exit;
  fPopupRepoRoot := lRepo;
  if fRepoStatusMap.TryGetValue(lRepo, lStatus) then
    miRepoCommit.Visible := lStatus.IsDirty
  else
    miRepoCommit.Visible := False;
  lPt := lBtn.ClientToScreen(Point(0, lBtn.Height));
  pmRepoActions.Popup(lPt.X, lPt.Y);
end;

procedure TfrmMain.RepoMenuClick(Sender: TObject);
var
  lAction: TRepoAction;
begin
  if fPopupRepoRoot = '' then
    Exit;
  if Sender = miRepoCommit then
    lAction := TRepoAction.raCommit
  else if Sender = miRepoFetch then
    lAction := TRepoAction.raFetch
  else if Sender = miRepoOpenFolder then
    lAction := TRepoAction.raOpenFolder
  else
    Exit;
  ExecuteRepoAction(lAction, fPopupRepoRoot);
end;

procedure TfrmMain.ExecuteRepoAction(const aAction: TRepoAction; const aRepoRoot: string);
var
  lMsg: string;
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
  else
    lActionName := rsOpenFolder;
  end;

  lMatched := [];
  lFetchRemote := '';
  if fRepoStatusMap.TryGetValue(aRepoRoot, lExisting) then
  begin
    lMatched := lExisting.MatchedFolders;
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
          end;

          if lOk then
            lMsg := Format('%s %s: %s', [cLogAction, lActionName, cLogActionOk])
          else
            lMsg := Format('%s %s: %s - %s', [cLogAction, lActionName, cLogActionFailed, lErr]);
        except
          on E: Exception do
          begin
            lMsg := Format('%s %s: %s - %s', [cLogAction, lActionName, cLogActionFailed, E.Message]);
          end;
        end;

        lStatusOk := False;
        lStatusErr := '';
        try
          lScanner := TRepoScanner.Create(fGit);
          try
            lStatusOk := lScanner.TryRefreshRepoStatus(fSettings, aRepoRoot, lMatched, lStatus, lStatusErr);
          finally
            lScanner.Free;
          end;
        except
          on E: Exception do
          begin
            lStatusOk := False;
            if lStatusErr = '' then
              lStatusErr := E.Message;
          end;
        end;

        if fShuttingDown then
          Exit;

        lEvent := Default(TUiEvent);
        lEvent.Kind := TUiEventKind.uekActionResult;
        lEvent.Text := lMsg;
        if lStatusOk then
          lEvent.RepoStatus := lStatus;
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
  lDialog: TFileOpenDialog;
begin
  lDialog := TFileOpenDialog.Create(nil);
  try
    lDialog.Options := lDialog.Options + [fdoPickFolders];
    lDialog.Title := rsStartPath;
    if edtStartPath.Text <> '' then
      lDialog.DefaultFolder := edtStartPath.Text;
    if lDialog.Execute then
      edtStartPath.Text := lDialog.FileName;
  finally
    lDialog.Free;
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

procedure TfrmMain.sbReposResize(Sender: TObject);
begin
  UpdateRepoCardWidths;
end;


procedure TfrmMain.UpdateRepoCardWidths;
var
  i: Integer;
  lWidth: Integer;
  lControl: TControl;
  lCard: TPanel;
begin
  if fpRepos = nil then
    Exit;
  lWidth := fpRepos.ClientWidth - fpRepos.Padding.Left - fpRepos.Padding.Right;
  if lWidth < 120 then
    lWidth := 120;
  for i := 0 to fpRepos.ControlCount - 1 do
  begin
    lControl := fpRepos.Controls[i];
    lControl.Width := lWidth;
    if lControl is TPanel then
    begin
      lCard := TPanel(lControl);
      UpdateRepoPathLabel(lCard);
    end;
  end;
end;

procedure TfrmMain.tmrUiTimer(Sender: TObject);
var
  lEvent: TUiEvent;
begin
  while fQueue.TryDequeue(lEvent) do
    HandleUiEvent(lEvent);
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
