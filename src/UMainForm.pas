unit UMainForm;

interface

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.Generics.Collections, System.ImageList, System.IOUtils,
  System.Skia, System.StrUtils, System.SyncObjs, System.SysUtils, System.Types,
  Winapi.ShellAPI, Winapi.Windows,
  Vcl.BaseImageCollection, Vcl.Buttons, Vcl.Clipbrd, Vcl.ComCtrls, Vcl.Controls, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.ImgList, Vcl.Menus, Vcl.Skia, Vcl.StdCtrls,
  Vcl.VirtualImageList,
  AdvTypes, VirtualTrees, VirtualTrees.Accessibility,
  AutoFree, AutoHourGlass, CancelToken, MaxLogic.ApplicationMessageManager, MaxLogic.Logger,
  UAppSettings, UBoundedParallel, UBulkActionResults, UFolderSelection, UFolderTreeFrame, UGitClient, UModels,
  UPathRules, URepoCache, URepoListModel, URepoPathDisplay, URepoScanner, URepositoryAccessibility,
  URepositoryExclusionsDialog, UScanPathsDialog, UStatusFilterHelp,
  UTextDetailsDialog, UTortoiseGit, UUiEventQueue;

type
  {$SCOPEDENUMS ON}
  TRepoAction = (raPull, raCommit, raPush, raFetch, raFixSubmoduleMain, raRescan, raOpenFolder);
  TRepoFilter = (rfAttention, rfOperationFailed, rfScanFailed, rfUnrelatedHistory,
    rfReadyToPull, rfBehindOnly, rfDiverged, rfAhead, rfDirty, rfDetached, rfNoIssues, rfAll);

  TRepositoryOperationKind = (rokDiscovery, rokAnalysis);
  TRepositoryOperationRequest = record
    Kind: TRepositoryOperationKind;
    Discovery: TRepoDiscoveryRequest;
    Analysis: TRepoAnalysisRequest;
    IgnorePath: string;
    DefaultIgnoreDirs: TArray<string>;
  end;

  TRepoActionRequest = record
    Action: TRepoAction;
    ActionName: string;
    RepoRoot: string;
    MessageText: string;
    MatchedFolders: TArray<string>;
    ParentRepoRoot: string;
    ParentMatchedFolders: TArray<string>;
    FetchRemote: string;
    IsBulk: Boolean;
  end;

  TfrmMain = class(TForm)
    pnlToolbar: TPanel;
    pnlToolbarContent: TPanel;
    FolderPane: TFolderTreeFrame;
    FolderSplitter: TSplitter;
    btnBrowseStart: TBitBtn;
    pnlFilterField: TPanel;
    cboTargetName: TComboBox;
    lblTargetName: TStaticText;
    btnFilterHelp: TBitBtn;
    btnExclusions: TBitBtn;
    pnlStatusFilter: TPanel;
    cboStatusFilter: TComboBox;
    lblStatusFilter: TStaticText;
    btnStatusFilterHelp: TBitBtn;
    pnlToolbarActions: TPanel;
    RepoTree: TVirtualStringTree;
    tmrUi: TTimer;
    btnScan: TBitBtn;
    btnAnalyzeRepos: TBitBtn;
    btnSettings: TBitBtn;
    btnPullVisible: TBitBtn;
    btnPushVisible: TBitBtn;
    pnlStatus: TPanel;
    btnShowLog: TBitBtn;
    btnClearFilters: TBitBtn;
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
    pnlActionThrottleField: TPanel;
    edtActionThrottle: TEdit;
    lblActionThrottle: TStaticText;
    pnlCacheField: TPanel;
    edtCacheTtl: TEdit;
    lblCacheTtl: TStaticText;
    chkDebugLog: TCheckBox;
    pnlDebugPathField: TPanel;
    edtDebugLogPath: TEdit;
    lblDebugLogPath: TStaticText;
    pmRepoActions: TPopupMenu;
    miRepoCommit: TMenuItem;
    miRepoFetch: TMenuItem;
    miRepoPull: TMenuItem;
    miRepoPush: TMenuItem;
    miRepoFixSubmoduleMain: TMenuItem;
    miRepoLastPullError: TMenuItem;
    miRepoLastPushError: TMenuItem;
    miRepoLastScanError: TMenuItem;
    miRepoSeparator: TMenuItem;
    miRepoTortoiseCommit: TMenuItem;
    miRepoTortoiseSync: TMenuItem;
    miRepoTortoiseLog: TMenuItem;
    miRepoRescan: TMenuItem;
    miRepoOpenSeparator: TMenuItem;
    miRepoOpenFolder: TMenuItem;
    pbProgress: TProgressBar;
    ActivityPanel: TPanel;
    ScanAnimation: TSkAnimatedImage;
    BulkAnimation: TSkAnimatedImage;
    lblScanActivity: TStaticText;
    ButtonImages: TVirtualImageList;
    ButtonSvgCollection: TAdvSVGImageCollection;
    BalloonHint: TBalloonHint;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnBrowseStartClick(Sender: TObject);
    procedure btnScanClick(Sender: TObject);
    procedure btnAnalyzeReposClick(aSender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnPullVisibleClick(Sender: TObject);
    procedure btnPushVisibleClick(Sender: TObject);
    procedure btnSettingsClick(Sender: TObject);
    procedure btnShowLogClick(Sender: TObject);
    procedure btnFilterHelpClick(Sender: TObject);
    procedure btnStatusFilterHelpClick(Sender: TObject);
    procedure cboStatusFilterChange(Sender: TObject);
    procedure cboTargetNameChange(Sender: TObject);
    procedure btnExclusionsClick(Sender: TObject);
    procedure btnClearFiltersClick(Sender: TObject);
    procedure pnlStatusDblClick(Sender: TObject);
    procedure RepoMenuClick(Sender: TObject);
    procedure RepoActionsPopup(aSender: TObject);
    procedure RepoTreeAfterCellPaint(aSender: TBaseVirtualTree; aTargetCanvas: TCanvas;
      aNode: PVirtualNode; aColumn: TColumnIndex; aCellRect: TRect);
    procedure RepoTreeGetText(aSender: TBaseVirtualTree; aNode: PVirtualNode;
      aColumn: TColumnIndex; aTextType: TVSTTextType; var aCellText: string);
    procedure RepoTreeMouseDown(aSender: TObject; aButton: TMouseButton; aShift: TShiftState;
      X, Y: Integer);
    procedure RepoTreeMouseLeave(aSender: TObject);
    procedure RepoTreeMouseMove(aSender: TObject; aShift: TShiftState; X, Y: Integer);
    procedure RepoTreeMouseUp(aSender: TObject; aButton: TMouseButton; aShift: TShiftState;
      X, Y: Integer);
    procedure RepoTreeKeyDown(aSender: TObject; var aKey: Word; aShift: TShiftState);
    procedure RepoTreePaintText(aSender: TBaseVirtualTree; const aTargetCanvas: TCanvas;
      aNode: PVirtualNode; aColumn: TColumnIndex; aTextType: TVSTTextType);
    procedure tmrUiTimer(Sender: TObject);
  protected
    procedure ApplyRepositoryExclusions(const aPatterns: TArray<string>);
    function RepositoryCachePath: string; virtual;
    function RepositoryCache: TRepoCache;
    procedure GetRepoActionRects(const aItem: TRepoListItem; const aCellRect: TRect;
      out aPullRect, aPushRect, aMoreRect: TRect);
    procedure PerformRepoAction(const aRequest: TRepoActionRequest);
    procedure AddWaitingRepo(const aRepoRoot: string);
    procedure HandleUiEvent(const aEvent: TUiEvent);
    function SelectedRepoRoot: string;
    procedure RefreshRepoTree(const aSelectionRoot: string = '');
    procedure ShowBulkActionSummary(const aCaption, aText: string); virtual;
    procedure ShowImmediateActionError(const aCaption, aText: string); virtual;
    procedure UpdateSearchFilterCaption(const aMatchedCount, aDiscoveredCount: Integer;
      const aHasCounts: Boolean);
  private
    fSettings: TAppSettings;
    fGit: TGitClient;
    fScanner: TRepoScanner;
    fQueue: TUiEventQueue;
    fScanThread: TThread;
    fOperationTerminalReceived: Boolean;
    fOperationCaption: string;
    fCacheLoadThread: TThread;
    fCacheLoading: Boolean;
    fCacheFilePath: string;
    fCancelToken: iCancelToken;
    fActionThreads: TList<TThread>;
    fActionLock: TCriticalSection;
    fActionBusyCount: Integer;
    fActionHourglass: IInterface;
    fBulkActionRunning: Boolean;
    fBulkActionName: string;
    fBulkActionTotal: Integer;
    fBulkResults: TBulkActionResults;
    fShuttingDown: Boolean;
    fPopupRepoRoot: string;
    fTortoiseGitExe: string;
    fRepoStatusMap: TDictionary<string, TRepoStatus>;
    fRepoListModel: TRepoListModel;
    fLastPullErrors: TDictionary<string, string>;
    fLastPushErrors: TDictionary<string, string>;
    fStatusFilter: TRepoFilter;
    fScanGeneration: Int64;
    fMaxUiBatchMilliseconds: Int64;
    fUiMetricsPending: Boolean;
    fRepoViewDirty: Boolean;
    fRepoViewSelectionRoot: string;
    fLastRepoViewFlushTick: UInt64;
    fHotRepoNode: PVirtualNode;
    fHotRepoButton: Integer;
    fRedirectMouseWheel: TAppMessagehandlerRedirectMouseWheel;
    procedure LoadSettingsToUi;
    procedure FolderSelectionChanged(aSender: TObject);
    procedure FolderDiscoverHere(aSender: TObject; const aPath: string);
    function ReadSettingsFromUi(out aError: string): Boolean;
    function ResolveIgnoreDirsPath: string;
    function GetRelativeRepoPath(const aRepoRoot: string): string;
    function BuildDirtyBadge(const aDirtySummary: string; out aHasFiles: Boolean): string;
    procedure UpdateStatusFilterItems;
    procedure StartScan;
    function CreateDiscoveryRequest: TRepositoryOperationRequest;
    procedure StartAnalysis(const aRoots: TArray<string>);
    procedure StartRepositoryOperation(const aRequest: TRepositoryOperationRequest);
    function RepositoryJobBlocked: Boolean;
    procedure FinishRepositoryOperation;
    procedure HandleRepositoryOperationFinished(const aEvent: TUiEvent);
    procedure ReconcileRepositoryInventory(const aRoots: TArray<string>);
    function LoadTraversalPatterns(const aPath: string;
      const aDefaults: TArray<string>): TArray<TIgnorePattern>;
    procedure StartCacheLoad;
    function BuildObservationText(const aStatus: TRepoStatus): string;
    procedure SetScanningState(const aScanning: Boolean);
    procedure SetBulkActionState(const aRunning: Boolean);
    procedure BeginActionBusy;
    procedure EndActionBusy(const aCount: Integer = 1);
    procedure ClearRepoPanels;
    procedure AddRepoPanel(const aStatus: TRepoStatus);
    procedure UpdateRepoPanel(const aStatus: TRepoStatus);
    procedure ApplyActionErrorState(const aEvent: TUiEvent);
    procedure MergeActionErrors(var aStatus: TRepoStatus);
    function RepoActionName(const aActionTag: Integer): string;
    function RepoItemForNode(const aNode: PVirtualNode; out aItem: TRepoListItem): Boolean;
    procedure SelectRepoRoot(const aRepoRoot: string);
    procedure QueueRepoViewRefresh(const aSelectionRoot: string);
    procedure FlushRepoView;
    function BuildRepoAccessibilityText(const aItem: TRepoListItem): string;
    procedure SetRepoHotButton(const aNode: PVirtualNode; const aButtonIndex: Integer);
    procedure PrepareRepoPopup(const aRepoRoot: string);
    procedure ShowRepoPopup(const aRepoRoot: string; const aPoint: TPoint);
    procedure QueueLog(const aText: string);
    procedure ApplyStatusFilter;
    procedure UpdateBulkActionButtons;
    procedure CopyTextToClipboard(const aText: string);
    procedure CopyStatusToClipboard;
    procedure RunBulkAction(const aAction: TRepoAction);
    procedure AddActionThread(const aThread: TThread);
    procedure CleanupFinishedActionThreads;
    procedure WaitForActionThreads;
    procedure ExecuteRepoAction(const aAction: TRepoAction; const aRepoRoot: string);
    procedure UpdateStatusText(const aText: string);
    function BuildRepoActionRequest(const aAction: TRepoAction; const aRepoRoot,
      aMessage: string): TRepoActionRequest;
    procedure RunRepoAction(const aAction: TRepoAction; const aRepoRoot: string; const aMessage: string);
  end;

var
  frmMain: TfrmMain;

implementation


uses
  MaxLogic.ioUtils, MaxLogic.StrUtils;

{$R *.dfm}

resourcestring
  rsNoMatchingRepositories = 'No repositories match the current filters. Clear filters or change folder selection.';
  rsVisibleRepositoryCount = 'Showing %d of %d known repositories.';
  rsFormCaption = 'RepoPulse - Scan Git Repos';
  rsSettingsHeader = 'Settings';
  rsTraversalOptions = 'Traversal &options...';
  rsStatusFilter = 'Status Filter';
  rsMaxDepth = 'Max depth';
  rsThrottle = 'Scan &threads';
  rsActionThrottle = 'Pull/Push t&hreads';
  rsCacheTtl = 'Refresh Interval';
  rsDebugLog = 'Debug log';
  rsDebugLogPath = 'Debug log path';
  rsFilterAttention = 'Needs attention';
  rsFilterOperationFailed = 'Operation failed';
  rsFilterScanFailed = 'Scan failed';
  rsFilterUnrelatedHistory = 'Unrelated history';
  rsFilterReadyToPull = 'Safe pull: clean and behind';
  rsFilterBehindOnly = 'Behind, not ahead';
  rsFilterDiverged = 'Diverged';
  rsFilterAhead = 'Ahead, not behind';
  rsFilterDirty = 'Dirty';
  rsFilterDetached = 'Detached';
  rsFilterNoIssues = 'No issues';
  rsFilterAll = 'All';
  rsFilterCountFmt = '%s (%d)';
  rsPullAll = 'Pull all';
  rsPushAll = 'Push all';
  rsPullVisibleHint = 'Runs Pull for every visible repository with a Pull action. ' +
    'Search Filter and Status Filter define the visible subset.';
  rsPushVisibleHint = 'Runs Push for every visible repository with a Push action. ' +
    'Search Filter and Status Filter define the visible subset.';
  rsSearchFilterHint = 'Filters known repositories immediately. Only matching repositories are shown, ' +
    'and Pull all and Push all use that visible subset.';
  rsStatusFilterHint = 'Narrows the current repository list. Pull all and Push all use only ' +
    'repositories visible in this status.';
  rsRescanAction = 'Rescan';
  rsRescanCaption = 'Analyze this repo';
  rsTortoiseGitCommit = 'TortoiseGit &Commit...';
  rsTortoiseGitSync = 'TortoiseGit &Sync...';
  rsTortoiseGitLog = 'TortoiseGit &Log...';
  rsLastPullError = 'Show last &Pull error...';
  rsLastPushError = 'Show last P&ush error...';
  rsLastScanError = 'Show last &Scan error...';
  rsLastPullErrorTitle = 'Last Pull error';
  rsLastPushErrorTitle = 'Last Push error';
  rsLastScanErrorTitle = 'Last Scan error';
  rsFilterHelpTitle = 'Search Filter Help';
  rsFilterHelp = 'The filter uses an Everything-inspired search syntax.'#13#10#13#10 +
    'Words separated by spaces must all match.'#13#10 +
    'Use | between alternatives: source|tests.'#13#10 +
    'Prefix a term with ! to exclude it: repo !archive.'#13#10 +
    'Use quotes to keep spaces together: "team tools".'#13#10 +
    'Use * for any text and ? for one character: max* or repo?.';
  rsSearchFilterCountFmt = '%s (%d of %d)';
  rsBulkProgressFmt = '%s %d of %d repositories...';
  rsBulkFinishedFmt = '%s finished for %d repositories.';
  rsBulkStoppedFmt = '%s stopped after %d of %d repositories.';
  rsBulkFailuresTitleFmt = '%s failures';
  rsBulkFinishedWithFailuresFmt = '%s finished: %d of %d repositories failed.';
  rsActionFailedTitleFmt = '%s failed: %s';
  rsPulling = 'Pulling';
  rsPushing = 'Pushing';

const
  rsTargetName = 'Search &Filter';
  rsScan = 'Update Repo list';
  rsAnalyzeRepos = 'Analyze Repos';
  rsScanActivity = 'Updating repository list...';
  rsAnalyzeActivity = 'Analyzing repositories...';
  rsDiscoveryOperation = 'Repository list update';
  rsAnalysisOperation = 'Repository analysis';
  rsDiscoveryComplete = 'Repository list updated: %d found, %d visible overall.';
  rsAnalysisComplete = 'Analysis completed: %d of %d repositories.';
  rsOperationCancelled = '%s cancelled.';
  rsOperationFailed = '%s failed: %s';
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
  rsErrMaxDepthNumber = 'MaxDepth must be a number';
  rsErrMaxDepthRange = 'MaxDepth must be >= 0';
  rsErrThrottleNumber = 'ThrottleLimit must be a number';
  rsErrThrottleRange = 'ThrottleLimit must be >= 1';
  rsErrActionThrottleNumber = 'Pull/Push threads must be a number';
  rsErrActionThrottleRange = 'Pull/Push threads must be >= 1';
  rsErrCacheTtlNumber = 'CacheTtlSeconds must be a number';
  rsErrCacheTtlRange = 'CacheTtlSeconds must be >= 0';
  rsBadgeBranch = 'Branch: ';
  rsBadgePullFailed = 'Pull failed';
  rsBadgePushFailed = 'Push failed';
  rsBadgeScanFailed = 'Scan failed';
  rsBadgeUnrelatedHistory = 'Unrelated history';
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
  rsStatusWaiting = 'Not analyzed';
  rsLoadingInventory = 'Loading saved repositories...';
  rsAnalysisRequired = 'Analyze this repository before changing it.';
  rsInventoryLoaded = 'Saved repositories loaded: %d';
  rsLastAnalyzed = 'Last analyzed %s';
  rsObservationNow = 'just now';
  rsObservationMinute = '%d minute ago';
  rsObservationMinutes = '%d minutes ago';
  rsObservationHour = '%d hour ago';
  rsObservationHours = '%d hours ago';
  rsObservationDay = '%d day ago';
  rsObservationDays = '%d days ago';
  rsObservationMonth = '%d month ago';
  rsObservationMonths = '%d months ago';
  rsObservationYear = '%d year ago';
  rsObservationYears = '%d years ago';
  rsObservationUnknown = 'at an unknown time';
  rsFixSubmoduleMissingRef = 'Cannot realign the branch because origin/main and origin/master are missing.';
  rsFixSubmoduleConfirm = 'This will run "git fetch --prune origin", "git reset --hard %s", and "git checkout -B %s %s".'#13#10 +
    'This discards local commits/changes in that repo. Continue?';

const
  cLogScanStarted = 'Repository operation started.';
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
  cClipboardRetryDelayMs = 10;
  cClipboardRetryTimeoutMs = 250;

procedure TfrmMain.UpdateSearchFilterCaption(const aMatchedCount, aDiscoveredCount: Integer;
  const aHasCounts: Boolean);
begin
  if aHasCounts and (Trim(cboTargetName.Text) <> '') then
    lblTargetName.Caption := Format(rsSearchFilterCountFmt,
      [rsTargetName, aMatchedCount, aDiscoveredCount])
  else
    lblTargetName.Caption := rsTargetName;
end;

function TfrmMain.RepositoryCache: TRepoCache;
begin
  Result := fScanner.Cache;
end;

function TfrmMain.RepositoryCachePath: string;
begin
  Result := TPath.Combine(TAppSettings.GetSettingsFolder, 'repo-scan-cache.json');
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  fSettings := TAppSettings.Create;
  fSettings.Load;

  fGit := TGitClient.Create;
  fCacheFilePath := RepositoryCachePath;
  fScanner := TRepoScanner.Create(fGit, nil, fCacheFilePath);
  fQueue := TUiEventQueue.Create;
  fRepoStatusMap := TDictionary<string, TRepoStatus>.Create;
  fRepoListModel := TRepoListModel.Create;
  fLastPullErrors := TDictionary<string, string>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  fLastPushErrors := TDictionary<string, string>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  fBulkResults := TBulkActionResults.Create;
  fActionThreads := TList<TThread>.Create;
  fActionLock := TCriticalSection.Create;
  fShuttingDown := False;
  fBulkActionRunning := False;
  fTortoiseGitExe := TTortoiseGit.DetectExecutable;

  Caption := rsFormCaption;
  lblSettingsHeader.Caption := rsSettingsHeader;
  btnBrowseStart.Caption := rsTraversalOptions;
  lblMaxDepth.Caption := rsMaxDepth;
  lblThrottle.Caption := rsThrottle;
  lblActionThrottle.Caption := rsActionThrottle;
  lblCacheTtl.Caption := rsCacheTtl;
  chkDebugLog.Caption := rsDebugLog;
  lblDebugLogPath.Caption := rsDebugLogPath;
  lblTargetName.Caption := rsTargetName;
  lblStatusFilter.Caption := rsStatusFilter;

  btnScan.Caption := rsScan;
  btnAnalyzeRepos.Caption := rsAnalyzeRepos;
  lblScanActivity.Caption := rsScanActivity;
  btnSettings.Caption := rsSettings;
  btnShowLog.Caption := rsShowLog;
  btnPullVisible.Caption := rsPullAll;
  btnPushVisible.Caption := rsPushAll;
  btnPullVisible.Hint := rsPullVisibleHint;
  btnPushVisible.Hint := rsPushVisibleHint;
  cboTargetName.Hint := rsSearchFilterHint;
  cboStatusFilter.Hint := rsStatusFilterHint;
  miRepoCommit.Caption := rsCommit;
  miRepoFetch.Caption := rsFetch;
  miRepoPull.Caption := rsPull;
  miRepoPush.Caption := rsPush;
  miRepoFixSubmoduleMain.Caption := rsFixSubmoduleMain;
  miRepoLastPullError.Caption := rsLastPullError;
  miRepoLastPushError.Caption := rsLastPushError;
  miRepoLastScanError.Caption := rsLastScanError;
  miRepoTortoiseCommit.Caption := rsTortoiseGitCommit;
  miRepoTortoiseSync.Caption := rsTortoiseGitSync;
  miRepoTortoiseLog.Caption := rsTortoiseGitLog;
  miRepoRescan.Caption := rsRescanCaption;
  miRepoOpenFolder.Caption := rsOpenFolder;
  miRepoTortoiseCommit.Visible := fTortoiseGitExe <> '';
  miRepoTortoiseSync.Visible := fTortoiseGitExe <> '';
  miRepoTortoiseLog.Visible := fTortoiseGitExe <> '';
  miRepoLastPullError.Visible := False;
  miRepoLastPushError.Visible := False;
  miRepoLastScanError.Visible := False;

  cboStatusFilter.Items.BeginUpdate;
  try
    cboStatusFilter.Items.Clear;
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterAttention, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterOperationFailed, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterScanFailed, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterUnrelatedHistory, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterReadyToPull, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterBehindOnly, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterDiverged, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterAhead, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterDirty, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterDetached, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterNoIssues, 0]));
    cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [rsFilterAll, 0]));
    cboStatusFilter.ItemIndex := 0;
  finally
    cboStatusFilter.Items.EndUpdate;
  end;
  fStatusFilter := TRepoFilter.rfAttention;

  LoadSettingsToUi;
  if (fSettings.StatusFilterIndex >= 0) and
    (fSettings.StatusFilterIndex <= Ord(High(TRepoFilter))) then
    fStatusFilter := TRepoFilter(fSettings.StatusFilterIndex);
  cboStatusFilter.ItemIndex := Ord(fStatusFilter);
  fRepoListModel.SetFilter(TRepoListFilter(Ord(fStatusFilter)));
  fRepoListModel.SetSearchQuery(cboTargetName.Text);
  fRepoListModel.SetExclusions(fSettings.RepositoryExclusions);
  SetScanningState(False);
  BulkAnimation.Animation.Loop := False;
  BulkAnimation.Animation.Enabled := False;
  BulkAnimation.Visible := False;
  pbProgress.Visible := False;
  fRedirectMouseWheel := TAppMessagehandlerRedirectMouseWheel.Create;
  tmrUi.Interval := 100;
  tmrUi.Enabled := True;
  UpdateStatusText(rsStatusReady);
  UpdateBulkActionButtons;
  UpdateStatusFilterItems;
  InstallRepositoryAccessibility(RepoTree);
  StartCacheLoad;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
var
  lFlushThread: TThread;
  lCacheError: string;
begin
  fShuttingDown := True;
  tmrUi.Enabled := False;
  ScanAnimation.Animation.Loop := False;
  ScanAnimation.Animation.Enabled := False;
  BulkAnimation.Animation.Loop := False;
  BulkAnimation.Animation.Enabled := False;
  FreeAndNil(fRedirectMouseWheel);

  if fScanThread <> nil then
  begin
    if fCancelToken <> nil then
    begin
      fCancelToken.Cancel;
    end;
    fScanThread.WaitFor;
    FreeAndNil(fScanThread);
  end;
  fCancelToken := nil;
  if fCacheLoadThread <> nil then
  begin
    fCacheLoadThread.WaitFor;
    FreeAndNil(fCacheLoadThread);
  end;
  WaitForActionThreads;
  lFlushThread := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        if not fScanner.Cache.FlushPending(fCacheFilePath, fSettings.CacheTtlSeconds, lCacheError) then
          Exit;
      except
        on E: Exception do
          lCacheError := E.Message;
      end;
    end);
  lFlushThread.FreeOnTerminate := False;
  try
    lFlushThread.Start;
    lFlushThread.WaitFor;
  finally
    lFlushThread.Free;
  end;
  if lCacheError <> '' then
    maxLog.Error('Cache save failed on shutdown: ' + lCacheError);
  if Assigned(fSettings) then
  begin
    fSettings.TargetRepoName := Trim(cboTargetName.Text);
    fSettings.FolderSelectionRules := FolderPane.Rules;
    fSettings.ExpandedFolders := FolderPane.ExpandedPaths;
    fSettings.FoldersPaneWidth := MulDiv(FolderPane.Width, 96, CurrentPPI);
    try
      fSettings.Save;
    except
      on E: Exception do
        maxLog.Error('Settings save failed: ' + E.Message);
    end;
  end;
  fBulkResults.Free;
  fLastPushErrors.Free;
  fLastPullErrors.Free;
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
  FolderPane.Width := MulDiv(fSettings.FoldersPaneWidth, CurrentPPI, 96);
  FolderPane.Initialize(fSettings.FolderSelectionRules, fSettings.ExpandedFolders);
  FolderPane.OnSelectionChanged := FolderSelectionChanged;
  FolderPane.OnDiscoverHere := FolderDiscoverHere;
  fRepoListModel.SetPathSelection(FolderPane.Rules);
  edtMaxDepth.Text := IntToStr(fSettings.MaxDepth);
  edtThrottle.Text := IntToStr(fSettings.ThrottleLimit);
  edtActionThrottle.Text := IntToStr(fSettings.ActionThrottleLimit);
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

procedure TfrmMain.FolderSelectionChanged(aSender: TObject);
var
  lSelectedRoot: string;
begin
  if fShuttingDown or (fRepoListModel = nil) then
    Exit;
  FlushRepoView;
  lSelectedRoot := SelectedRepoRoot;
  fSettings.FolderSelectionRules := FolderPane.Rules;
  fRepoListModel.SetPathSelection(fSettings.FolderSelectionRules);
  RefreshRepoTree(lSelectedRoot);
  UpdateBulkActionButtons;
  UpdateStatusFilterItems;
  UpdateSearchFilterCaption(fRepoListModel.VisibleCount, fRepoListModel.Count, True);
end;

procedure TfrmMain.FolderDiscoverHere(aSender: TObject; const aPath: string);
var
  lRequest: TRepositoryOperationRequest;
  lError, lSearchText: string;
begin
  if RepositoryJobBlocked or (Trim(aPath) = '') then
    Exit;
  lSearchText := cboTargetName.Text;
  if not ReadSettingsFromUi(lError) then
  begin
    MessageDlg(rsInvalidInput + lError, mtWarning, [mbOK], 0);
    Exit;
  end;
  cboTargetName.Text := lSearchText;
  fSettings.TargetRepoName := lSearchText;
  fSettings.Save;
  lRequest := CreateDiscoveryRequest;
  lRequest.Discovery.Roots := [aPath];
  lRequest.Discovery.Rules := [];
  lRequest.Discovery.UsePathSelection := False;
  StartRepositoryOperation(lRequest);
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
begin
  aError := '';
  Result := False;

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

  if not TryStrToInt(Trim(edtActionThrottle.Text), lNum) then
  begin
    aError := rsErrActionThrottleNumber;
    Exit(False);
  end;
  if lNum < 1 then
  begin
    aError := rsErrActionThrottleRange;
    Exit(False);
  end;
  fSettings.ActionThrottleLimit := lNum;

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
  Result := BuildRelativeRepoPath(aRepoRoot, SelectedFolderRoots(FolderPane.Rules));
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
  FlushRepoView;
  lSelectedRoot := SelectedRepoRoot;
  fRepoListModel.SetFilter(TRepoListFilter(Ord(fStatusFilter)));
  RefreshRepoTree(lSelectedRoot);
  UpdateBulkActionButtons;
  UpdateStatusFilterItems;
  fSettings.StatusFilterIndex := Ord(fStatusFilter);
end;

procedure TfrmMain.cboTargetNameChange(Sender: TObject);
var
  lSelectedRoot: string;
begin
  if fRepoListModel = nil then
    Exit;
  FlushRepoView;
  lSelectedRoot := SelectedRepoRoot;
  fRepoListModel.SetSearchQuery(cboTargetName.Text);
  RefreshRepoTree(lSelectedRoot);
  UpdateBulkActionButtons;
  UpdateStatusFilterItems;
  UpdateSearchFilterCaption(fRepoListModel.VisibleCount, fRepoListModel.Count, True);
end;

procedure TfrmMain.ApplyRepositoryExclusions(const aPatterns: TArray<string>);
var
  lSelectedRoot: string;
begin
  FlushRepoView;
  lSelectedRoot := SelectedRepoRoot;
  fSettings.RepositoryExclusions := Copy(aPatterns);
  fRepoListModel.SetExclusions(aPatterns);
  RefreshRepoTree(lSelectedRoot);
  UpdateBulkActionButtons;
  UpdateStatusFilterItems;
  UpdateSearchFilterCaption(fRepoListModel.VisibleCount, fRepoListModel.Count, True);
end;

procedure TfrmMain.btnExclusionsClick(Sender: TObject);
var
  lDialog: TRepositoryExclusionsDialog;
begin
  lDialog := TRepositoryExclusionsDialog.Create(Self);
  try
    lDialog.Initialize(fRepoListModel, fSettings.RepositoryExclusions);
    if lDialog.ShowModal = mrOk then
      ApplyRepositoryExclusions(lDialog.Patterns);
  finally
    lDialog.Free;
  end;
end;

procedure TfrmMain.btnClearFiltersClick(Sender: TObject);
var
  lSelectedRoot: string;
begin
  FlushRepoView;
  lSelectedRoot := SelectedRepoRoot;
  cboTargetName.Text := '';
  fRepoListModel.SetSearchQuery('');
  fStatusFilter := TRepoFilter.rfAll;
  cboStatusFilter.ItemIndex := Ord(fStatusFilter);
  fRepoListModel.SetFilter(TRepoListFilter.rlfAll);
  fSettings.StatusFilterIndex := Ord(fStatusFilter);
  ApplyRepositoryExclusions([]);
  RefreshRepoTree(lSelectedRoot);
end;

procedure TfrmMain.UpdateStatusFilterItems;
var
  lCounts: array[TRepoFilter] of Integer;
  lFilter: TRepoFilter;
  lIndex: Integer;
  lNames: array[TRepoFilter] of string;
  lRepopulate: Boolean;
begin
  lNames[TRepoFilter.rfAttention] := rsFilterAttention;
  lNames[TRepoFilter.rfOperationFailed] := rsFilterOperationFailed;
  lNames[TRepoFilter.rfScanFailed] := rsFilterScanFailed;
  lNames[TRepoFilter.rfUnrelatedHistory] := rsFilterUnrelatedHistory;
  lNames[TRepoFilter.rfReadyToPull] := rsFilterReadyToPull;
  lNames[TRepoFilter.rfBehindOnly] := rsFilterBehindOnly;
  lNames[TRepoFilter.rfDiverged] := rsFilterDiverged;
  lNames[TRepoFilter.rfAhead] := rsFilterAhead;
  lNames[TRepoFilter.rfDirty] := rsFilterDirty;
  lNames[TRepoFilter.rfDetached] := rsFilterDetached;
  lNames[TRepoFilter.rfNoIssues] := rsFilterNoIssues;
  lNames[TRepoFilter.rfAll] := rsFilterAll;
  for lFilter := Low(TRepoFilter) to High(TRepoFilter) do
    lCounts[lFilter] := fRepoListModel.FilterCount(TRepoListFilter(Ord(lFilter)));

  lIndex := cboStatusFilter.ItemIndex;
  cboStatusFilter.Items.BeginUpdate;
  try
    lRepopulate := cboStatusFilter.Items.Count <> Length(lNames);
    if lRepopulate then
      cboStatusFilter.Items.Clear;
    for lFilter := Low(TRepoFilter) to High(TRepoFilter) do
    begin
      if lRepopulate then
        cboStatusFilter.Items.Add(Format(rsFilterCountFmt, [lNames[lFilter], lCounts[lFilter]]))
      else
        cboStatusFilter.Items[Ord(lFilter)] := Format(rsFilterCountFmt,
          [lNames[lFilter], lCounts[lFilter]]);
    end;
  finally
    cboStatusFilter.Items.EndUpdate;
  end;
  if (lIndex >= 0) and (lIndex < cboStatusFilter.Items.Count) then
    cboStatusFilter.ItemIndex := lIndex
  else if cboStatusFilter.Items.Count > 0 then
    cboStatusFilter.ItemIndex := 0;
  UpdateSearchFilterCaption(fRepoListModel.VisibleCount, fRepoListModel.Count,
    fRepoListModel.Count > 0);
  if (fRepoListModel.Count > 0) and (fRepoListModel.VisibleCount = 0) then
    UpdateStatusText(rsNoMatchingRepositories)
  else if stsMain.SimpleText = rsNoMatchingRepositories then
    UpdateStatusText(Format(rsVisibleRepositoryCount,
      [fRepoListModel.VisibleCount, fRepoListModel.Count]));
end;

procedure TfrmMain.UpdateBulkActionButtons;
var
  lBlocked: Boolean;
begin
  lBlocked := RepositoryJobBlocked;
  FolderPane.DiscoveryEnabled := not lBlocked;
  btnScan.Enabled := (fScanThread <> nil) or not lBlocked;
  btnAnalyzeRepos.Enabled := not lBlocked and (fRepoListModel.VisibleCount > 0);
  btnPullVisible.Enabled := fRepoListModel.HasVisibleAction(TRepoListAction.rlaPull) and
    not lBlocked;
  btnPushVisible.Enabled := fRepoListModel.HasVisibleAction(TRepoListAction.rlaPush) and
    not lBlocked;
end;

procedure TfrmMain.CopyTextToClipboard(const aText: string);
var
  lStopwatch: TStopwatch;
begin
  lStopwatch := TStopwatch.StartNew;
  repeat
    try
      Clipboard.AsText := aText;
      Exit;
    except
      on EClipboardException do
      begin
        if lStopwatch.ElapsedMilliseconds >= cClipboardRetryTimeoutMs then
          raise;
      end;
    end;
    TThread.Sleep(cClipboardRetryDelayMs);
  until False;
end;

procedure TfrmMain.CopyStatusToClipboard;
var
  lText: string;
begin
  lText := Trim(stsMain.SimpleText);
  if lText = '' then
    Exit;
  CopyTextToClipboard(lText);
end;

procedure TfrmMain.ShowBulkActionSummary(const aCaption, aText: string);
begin
  TfrmTextDetailsDialog.ShowDetails(aCaption, aText);
end;

procedure TfrmMain.ShowImmediateActionError(const aCaption, aText: string);
begin
  TfrmTextDetailsDialog.ShowDetails(aCaption, aText);
end;

procedure TfrmMain.RunBulkAction(const aAction: TRepoAction);
var
  lActionName: string;
  lDone: Integer;
  lError: string;
  lEvent: TUiEvent;
  i: Integer;
  lMaxThreads: Integer;
  lProgressVerb: string;
  lRequests: TArray<TRepoActionRequest>;
  lRepoRoots: TArray<string>;
  lThread: TThread;
  lTotal: Integer;
begin
  if fShuttingDown or RepositoryJobBlocked then
    Exit;
  if not ReadSettingsFromUi(lError) then
  begin
    MessageDlg(rsInvalidInput + lError, mtWarning, [mbOK], 0);
    Exit;
  end;
  fSettings.Save;
  case aAction of
    TRepoAction.raPull:
      begin
        lActionName := rsPull;
        lProgressVerb := rsPulling;
        lRepoRoots := fRepoListModel.VisibleActionRoots(TRepoListAction.rlaPull);
      end;
    TRepoAction.raPush:
      begin
        lActionName := rsPush;
        lProgressVerb := rsPushing;
        lRepoRoots := fRepoListModel.VisibleActionRoots(TRepoListAction.rlaPush);
      end;
  else
    Exit;
  end;
  if Length(lRepoRoots) = 0 then
    Exit;

  lTotal := Length(lRepoRoots);
  fBulkActionName := lActionName;
  fBulkActionTotal := lTotal;
  fBulkResults.Clear;
  SetLength(lRequests, lTotal);
  for i := 0 to lTotal - 1 do
  begin
    lRequests[i] := BuildRepoActionRequest(aAction, lRepoRoots[i], '');
    lRequests[i].IsBulk := True;
  end;
  lMaxThreads := fSettings.ActionThrottleLimit;
  lDone := 0;

  lEvent := Default(TUiEvent);
  lEvent.Kind := TUiEventKind.uekProgressStart;
  lEvent.ProgressMode := TProgressMode.pmDeterminate;
  lEvent.ProgressMax := lTotal;
  lEvent.ActionTag := Ord(aAction);
  lEvent.Text := Format(rsBulkProgressFmt, [lProgressVerb, 0, lTotal]);
  HandleUiEvent(lEvent);

  CleanupFinishedActionThreads;
  BeginActionBusy;
  try
    lThread := TThread.CreateAnonymousThread(
      procedure
      var
        lEndEvent: TUiEvent;
        lFailed: Boolean;
      begin
        lFailed := False;
        try
          TBoundedParallel.Run(lTotal, lMaxThreads,
            procedure(aIndex: Integer)
            var
              lCompleted: Integer;
              lProgressEvent: TUiEvent;
            begin
              PerformRepoAction(lRequests[aIndex]);
              lCompleted := TInterlocked.Increment(lDone);
              lProgressEvent := Default(TUiEvent);
              lProgressEvent.Kind := TUiEventKind.uekProgressUpdate;
              lProgressEvent.ProgressMax := lTotal;
              lProgressEvent.ProgressValue := lCompleted;
              lProgressEvent.Text := Format(rsBulkProgressFmt,
                [lProgressVerb, lCompleted, lTotal]);
              fQueue.Enqueue(lProgressEvent);
            end);
        except
          on E: Exception do
          begin
            lFailed := True;
            lEndEvent := Default(TUiEvent);
            lEndEvent.Kind := TUiEventKind.uekLog;
            lEndEvent.Text := 'Bulk action coordinator failed: ' + E.ClassName + ' - ' + E.Message;
            fQueue.Enqueue(lEndEvent);
          end;
        end;
        lEndEvent := Default(TUiEvent);
        lEndEvent.Kind := TUiEventKind.uekProgressEnd;
        lEndEvent.ActionTag := Ord(aAction);
        if lFailed then
          lEndEvent.Text := Format(rsBulkStoppedFmt, [lActionName, lDone, lTotal])
        else
          lEndEvent.Text := Format(rsBulkFinishedFmt, [lActionName, lTotal]);
        fQueue.Enqueue(lEndEvent);
      end);
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

procedure TfrmMain.SetScanningState(const aScanning: Boolean);
begin
  ActivityPanel.Visible := aScanning;
  ScanAnimation.Visible := aScanning;
  BulkAnimation.Visible := False;
  if aScanning then
  begin
    lblScanActivity.Caption := fOperationCaption;
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
  pnlSettingsContent.Enabled := not aScanning;
  btnAnalyzeRepos.Enabled := not aScanning and not RepositoryJobBlocked and
    (fRepoListModel.VisibleCount > 0);
  if aScanning then
  begin
    btnPullVisible.Enabled := False;
    btnPushVisible.Enabled := False;
  end else begin
    UpdateBulkActionButtons;
  end;
end;

procedure TfrmMain.SetBulkActionState(const aRunning: Boolean);
begin
  fBulkActionRunning := aRunning;
  ActivityPanel.Visible := aRunning;
  ScanAnimation.Visible := False;
  BulkAnimation.Visible := aRunning;
  if aRunning then
  begin
    BulkAnimation.Animation.Loop := True;
    BulkAnimation.Animation.Enabled := True;
    BulkAnimation.Animation.Start;
  end else begin
    BulkAnimation.Animation.Loop := False;
    BulkAnimation.Animation.Enabled := False;
  end;
  btnScan.Enabled := not aRunning;
  btnAnalyzeRepos.Enabled := not aRunning and not RepositoryJobBlocked and
    (fRepoListModel.VisibleCount > 0);
  btnSettings.Enabled := not aRunning;
  btnBrowseStart.Enabled := not aRunning;
  cboTargetName.Enabled := not aRunning;
  cboStatusFilter.Enabled := not aRunning;
  pnlSettingsContent.Enabled := not aRunning;
  UpdateBulkActionButtons;
end;

procedure TfrmMain.BeginActionBusy;
begin
  Inc(fActionBusyCount);
  if fActionBusyCount = 1 then
    fActionHourglass := AutoHourGlass.MakeCHG;
  UpdateBulkActionButtons;
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
  if not fShuttingDown then
    UpdateBulkActionButtons;
end;

procedure TfrmMain.ClearRepoPanels;
begin
  SetRepoHotButton(nil, 0);
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
  lSelectedRoot: string;
begin
  lSelectedRoot := SelectedRepoRoot;
  lCount := fRepoListModel.Count;
  fRepoListModel.AddWaiting(aRepoRoot, GetRelativeRepoPath(aRepoRoot));
  if fRepoListModel.Count <> lCount then
    QueueRepoViewRefresh(lSelectedRoot);
end;

procedure TfrmMain.AddRepoPanel(const aStatus: TRepoStatus);
var
  lStatus: TRepoStatus;
  lSelectedRoot: string;
begin
  lSelectedRoot := SelectedRepoRoot;
  lStatus := aStatus;
  MergeActionErrors(lStatus);
  fRepoStatusMap.AddOrSetValue(lStatus.RepoRoot, lStatus);
  fRepoListModel.AddOrUpdate(lStatus, GetRelativeRepoPath(lStatus.RepoRoot));
  QueueRepoViewRefresh(lSelectedRoot);
end;

procedure TfrmMain.UpdateRepoPanel(const aStatus: TRepoStatus);
begin
  AddRepoPanel(aStatus);
end;

procedure TfrmMain.ApplyActionErrorState(const aEvent: TUiEvent);
var
  lError: string;
begin
  if aEvent.RepoRoot = '' then
    Exit;
  lError := aEvent.ActionError;
  if Trim(lError) = '' then
    lError := TBulkActionResults.SignificantLine(lError);
  if aEvent.ActionTag = Ord(TRepoAction.raPull) then
  begin
    if aEvent.ActionSucceeded then
      fLastPullErrors.Remove(aEvent.RepoRoot)
    else
      fLastPullErrors.AddOrSetValue(aEvent.RepoRoot, lError);
  end else if aEvent.ActionTag = Ord(TRepoAction.raPush) then
  begin
    if aEvent.ActionSucceeded then
      fLastPushErrors.Remove(aEvent.RepoRoot)
    else
      fLastPushErrors.AddOrSetValue(aEvent.RepoRoot, lError);
  end;
end;

procedure TfrmMain.MergeActionErrors(var aStatus: TRepoStatus);
begin
  if not fLastPullErrors.TryGetValue(aStatus.RepoRoot, aStatus.LastPullError) then
    aStatus.LastPullError := '';
  if not fLastPushErrors.TryGetValue(aStatus.RepoRoot, aStatus.LastPushError) then
    aStatus.LastPushError := '';
end;

function TfrmMain.RepoActionName(const aActionTag: Integer): string;
begin
  if aActionTag = Ord(TRepoAction.raPull) then
    Result := rsPull
  else if aActionTag = Ord(TRepoAction.raPush) then
    Result := rsPush
  else
    Result := cLogAction;
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
  SetRepoHotButton(nil, 0);
  RepoTree.BeginUpdate;
  try
    RepoTree.RootNodeCount := fRepoListModel.VisibleCount;
    RepoTree.Invalidate;
  finally
    RepoTree.EndUpdate;
  end;
  SelectRepoRoot(aSelectionRoot);
end;

procedure TfrmMain.QueueRepoViewRefresh(const aSelectionRoot: string);
begin
  if not fRepoViewDirty then
    fRepoViewSelectionRoot := aSelectionRoot;
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

function TfrmMain.BuildObservationText(const aStatus: TRepoStatus): string;
var
  lObservedUtc, lNowUtc: TDateTime;
  lAgeMinutes, lCount: Int64;
  lWhen: string;
begin
  Result := '';
  if aStatus.LastAnalyzedUtc = '' then
    Exit;
  lNowUtc := TTimeZone.Local.ToUniversalTime(Now);
  if not TryISO8601ToDate(aStatus.LastAnalyzedUtc, lObservedUtc, True) then
    lWhen := rsObservationUnknown
  else if lObservedUtc > lNowUtc then
    lWhen := rsObservationUnknown
  else
  begin
    lAgeMinutes := MinutesBetween(lNowUtc, lObservedUtc);
    if lAgeMinutes = 0 then
      lWhen := rsObservationNow
    else if lAgeMinutes < 60 then
    begin
      if lAgeMinutes = 1 then
        lWhen := Format(rsObservationMinute, [lAgeMinutes])
      else
        lWhen := Format(rsObservationMinutes, [lAgeMinutes]);
    end else if lAgeMinutes < 24 * 60 then
    begin
      lCount := lAgeMinutes div 60;
      if lCount = 1 then
        lWhen := Format(rsObservationHour, [lCount])
      else
        lWhen := Format(rsObservationHours, [lCount]);
    end else if lAgeMinutes < 30 * 24 * 60 then
    begin
      lCount := lAgeMinutes div (24 * 60);
      if lCount = 1 then
        lWhen := Format(rsObservationDay, [lCount])
      else
        lWhen := Format(rsObservationDays, [lCount]);
    end else if lAgeMinutes < 365 * 24 * 60 then
    begin
      lCount := lAgeMinutes div (30 * 24 * 60);
      if lCount = 1 then
        lWhen := Format(rsObservationMonth, [lCount])
      else
        lWhen := Format(rsObservationMonths, [lCount]);
    end else begin
      lCount := lAgeMinutes div (365 * 24 * 60);
      if lCount = 1 then
        lWhen := Format(rsObservationYear, [lCount])
      else
        lWhen := Format(rsObservationYears, [lCount]);
    end;
  end;
  Result := Format(rsLastAnalyzed, [lWhen]);
end;

function TfrmMain.BuildRepoAccessibilityText(const aItem: TRepoListItem): string;
var
  lDirty, lObservation: string;
  lHasFiles: Boolean;
begin
  Result := aItem.DisplayPath;
  if aItem.State = TRepoListItemState.rlisWaiting then
    Exit(Result + '. ' + rsStatusWaiting);
  lObservation := BuildObservationText(aItem.Status);
  if lObservation <> '' then
    Result := Result + '. ' + lObservation;
  if Trim(aItem.Status.LastPullError) <> '' then
    Result := Result + '. ' + rsBadgePullFailed;
  if Trim(aItem.Status.LastPushError) <> '' then
    Result := Result + '. ' + rsBadgePushFailed;
  if aItem.Status.ScanFailed then
    Exit(Result + '. ' + rsBadgeScanFailed);
  Result := Result + '. ' + rsBadgeBranch + aItem.Status.Branch;
  if aItem.Status.FetchFailed then
    Result := Result + '. ' + rsBadgeFetchFailed
  else if not aItem.Status.HasOrigin then
    Result := Result + '. ' + rsBadgeNoOrigin
  else if aItem.Status.Upstream = '' then
    Result := Result + '. ' + rsBadgeNoUpstream
  else if aItem.Status.UnrelatedHistory then
    Result := Result + '. ' + rsBadgeUnrelatedHistory
  else if aItem.Status.IsOutOfDate then
    Result := Result + '. ' + rsBadgeBehind + IntToStr(aItem.Status.Behind)
  else if aItem.Status.HasUnpushed then
    Result := Result + '. ' + rsBadgeAhead + IntToStr(aItem.Status.Ahead)
  else
    Result := Result + '. ' + rsBadgeSyncOk;
  if aItem.Status.SubmoduleNeedsMainFastForward and (not aItem.Status.UnrelatedHistory) then
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
  if (aItem.State <> TRepoListItemState.rlisReady) or aItem.Status.IsCached or
    aItem.Status.ScanFailed then
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
  lCanMutate, lCanPull, lCanPush: Boolean;
begin
  fPopupRepoRoot := aRepoRoot;
  lCanMutate := False;
  lCanPull := False;
  lCanPush := False;
  if fRepoStatusMap.TryGetValue(aRepoRoot, lStatus) then
  begin
    lCanMutate := not RepositoryJobBlocked and not lStatus.IsCached and not lStatus.ScanFailed;
    lCanPull := lCanMutate and lStatus.IsOutOfDate and not lStatus.UnrelatedHistory;
    lCanPush := lCanMutate and lStatus.IsDirty;
    miRepoCommit.Visible := lStatus.IsDirty;
    miRepoFixSubmoduleMain.Visible := lStatus.SubmoduleNeedsMainFastForward;
    miRepoLastPullError.Visible := Trim(lStatus.LastPullError) <> '';
    miRepoLastPushError.Visible := Trim(lStatus.LastPushError) <> '';
    miRepoLastScanError.Visible := lStatus.ScanFailed and (Trim(lStatus.ScanError) <> '');
  end else begin
    miRepoCommit.Visible := False;
    miRepoFixSubmoduleMain.Visible := False;
    miRepoLastPullError.Visible := False;
    miRepoLastPushError.Visible := False;
    miRepoLastScanError.Visible := False;
  end;
  miRepoFetch.Enabled := not RepositoryJobBlocked;
  miRepoPull.Enabled := lCanPull;
  miRepoPush.Enabled := lCanPush;
  miRepoRescan.Enabled := not RepositoryJobBlocked;
  miRepoCommit.Enabled := lCanMutate;
  miRepoFixSubmoduleMain.Enabled := lCanMutate;
  miRepoTortoiseCommit.Enabled := lCanMutate;
  miRepoTortoiseSync.Enabled := lCanMutate;
  miRepoTortoiseCommit.Visible := fTortoiseGitExe <> '';
  miRepoTortoiseSync.Visible := fTortoiseGitExe <> '';
  miRepoTortoiseLog.Visible := fTortoiseGitExe <> '';
end;

procedure TfrmMain.HandleUiEvent(const aEvent: TUiEvent);
var
  lActionName: string;
  lDialogTitle: string;
  lErrorText: string;
  lStatus: TRepoStatus;
begin
  case aEvent.Kind of
    TUiEventKind.uekInventoryLoaded:
      begin
        fCacheLoading := False;
        btnScan.Enabled := (fScanThread = nil) and not fBulkActionRunning;
        memLog.Lines.Add(aEvent.Text);
        UpdateStatusText(aEvent.Text);
        UpdateBulkActionButtons;
        UpdateStatusFilterItems;
      end;
    TUiEventKind.uekLog:
      begin
        memLog.Lines.Add(aEvent.Text);
        UpdateStatusText(aEvent.Text);
      end;
    TUiEventKind.uekProgressStart:
      begin
        if (aEvent.Generation = 0) and (aEvent.Text <> '') then
        begin
          fBulkResults.Clear;
          fBulkActionName := RepoActionName(aEvent.ActionTag);
          fBulkActionTotal := aEvent.ProgressMax;
          SetBulkActionState(True);
          lblScanActivity.Caption := aEvent.Text;
        end;
        pbProgress.Visible := True;
        if aEvent.ProgressMode = TProgressMode.pmIndeterminate then
        begin
          pbProgress.Style := pbstMarquee;
        end else begin
          pbProgress.Style := pbstNormal;
          pbProgress.Max := aEvent.ProgressMax;
          pbProgress.Position := aEvent.ProgressValue;
        end;
        if aEvent.Text <> '' then
          UpdateStatusText(aEvent.Text)
        else if aEvent.Generation <> 0 then
          UpdateStatusText(fOperationCaption)
        else
          UpdateStatusText(rsStatusScanning);
      end;
    TUiEventKind.uekProgressUpdate:
      begin
        if pbProgress.Style = pbstNormal then
          pbProgress.Position := aEvent.ProgressValue;
        if aEvent.Text <> '' then
        begin
          lblScanActivity.Caption := aEvent.Text;
          UpdateStatusText(aEvent.Text);
        end;
      end;
    TUiEventKind.uekProgressEnd:
      begin
        pbProgress.Visible := False;
        pbProgress.Position := 0;
        if (aEvent.Generation = 0) and fBulkActionRunning then
        begin
          SetBulkActionState(False);
          if fBulkResults.Count > 0 then
          begin
            UpdateStatusText(Format(rsBulkFinishedWithFailuresFmt,
              [fBulkActionName, fBulkResults.Count, fBulkActionTotal]));
            lDialogTitle := Format(rsBulkFailuresTitleFmt, [fBulkActionName]);
            ShowBulkActionSummary(lDialogTitle,
              fBulkResults.BuildReport(fBulkActionName, fBulkActionTotal));
          end else if aEvent.Text <> '' then
            UpdateStatusText(aEvent.Text);
          fBulkResults.Clear;
          fBulkActionName := '';
          fBulkActionTotal := 0;
        end else if aEvent.Text <> '' then
          UpdateStatusText(aEvent.Text);
      end;
    TUiEventKind.uekRepoWaiting, TUiEventKind.uekDiscoveryFound:
      AddWaitingRepo(aEvent.RepoRoot);
    TUiEventKind.uekRepoResult:
      AddRepoPanel(aEvent.RepoStatus);
    TUiEventKind.uekAnalysisFinished:
      HandleRepositoryOperationFinished(aEvent);
    TUiEventKind.uekDiscoveryFinished:
      begin
        ReconcileRepositoryInventory(aEvent.RepoRoots);
        HandleRepositoryOperationFinished(aEvent);
      end;
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
        ApplyActionErrorState(aEvent);
        if aEvent.RepoStatus.RepoRoot <> '' then
          UpdateRepoPanel(aEvent.RepoStatus);
        if (aEvent.RepoStatus.RepoRoot = '') and (aEvent.RepoRoot <> '') and
          fRepoStatusMap.TryGetValue(aEvent.RepoRoot, lStatus) then
          UpdateRepoPanel(lStatus);
        if aEvent.RelatedRepoStatus.RepoRoot <> '' then
          UpdateRepoPanel(aEvent.RelatedRepoStatus);
        if aEvent.ActionIsBulk then
        begin
          if not aEvent.ActionSucceeded then
            fBulkResults.AddFailure(aEvent.RepoRoot, aEvent.ActionError);
        end else if (not aEvent.ActionSucceeded) and
          ((aEvent.ActionTag = Ord(TRepoAction.raPull)) or
           (aEvent.ActionTag = Ord(TRepoAction.raPush))) then
        begin
          lActionName := RepoActionName(aEvent.ActionTag);
          lDialogTitle := Format(rsActionFailedTitleFmt, [lActionName, aEvent.RepoRoot]);
          lErrorText := aEvent.ActionError;
          if Trim(lErrorText) = '' then
            lErrorText := TBulkActionResults.SignificantLine(lErrorText);
          ShowImmediateActionError(lDialogTitle, lErrorText);
        end;
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

procedure TfrmMain.StartCacheLoad;
begin
  fCacheLoading := True;
  btnScan.Enabled := False;
  UpdateStatusText(rsLoadingInventory);
  UpdateBulkActionButtons;
  fCacheLoadThread := TThread.CreateAnonymousThread(
    procedure
    var
      lEvent: TUiEvent;
      lRoot, lError, lCompletion: string;
      lRoots: TArray<string>;
      lStatus: TRepoStatus;
    begin
      lCompletion := '';
      try
        if fScanner.Cache.EnsureLoaded(fCacheFilePath, lError) then
        begin
          lRoots := fScanner.Cache.GetInventory;
          for lRoot in lRoots do
          begin
            lEvent := Default(TUiEvent);
            if fScanner.Cache.TryGetStatus(lRoot, lStatus) then
            begin
              lEvent.Kind := TUiEventKind.uekRepoResult;
              lEvent.RepoStatus := lStatus;
            end else begin
              lEvent.Kind := TUiEventKind.uekRepoWaiting;
              lEvent.RepoRoot := lRoot;
            end;
            fQueue.Enqueue(lEvent);
          end;
          lCompletion := Format(rsInventoryLoaded, [Length(lRoots)]);
        end else
          lCompletion := 'Cache load failed: ' + lError;
      except
        on E: Exception do
          lCompletion := 'Cache load failed: ' + E.Message;
      end;
      lEvent := Default(TUiEvent);
      lEvent.Kind := TUiEventKind.uekInventoryLoaded;
      lEvent.Text := lCompletion;
      fQueue.Enqueue(lEvent);
    end);
  fCacheLoadThread.FreeOnTerminate := False;
  fCacheLoadThread.Start;
end;

procedure TfrmMain.StartScan;
var
  lRequest: TRepositoryOperationRequest;
begin
  if RepositoryJobBlocked then
    Exit;
  lRequest := CreateDiscoveryRequest;
  if Length(lRequest.Discovery.Roots) = 0 then
    Exit;
  StartRepositoryOperation(lRequest);
end;

function TfrmMain.CreateDiscoveryRequest: TRepositoryOperationRequest;
begin
  Result := Default(TRepositoryOperationRequest);
  Result.Kind := TRepositoryOperationKind.rokDiscovery;
  Result.Discovery.Rules := FolderPane.Rules;
  Result.Discovery.Roots := SelectedFolderRoots(Result.Discovery.Rules);
  Result.Discovery.UsePathSelection := True;
  Result.Discovery.MaxDepth := fSettings.MaxDepth;
  Result.Discovery.CacheTtlSeconds := fSettings.CacheTtlSeconds;
  Result.Discovery.DebugLogEnabled := fSettings.DebugLogEnabled;
  Result.IgnorePath := ResolveIgnoreDirsPath;
  Result.DefaultIgnoreDirs := Copy(fSettings.ExcludeDirs);
end;

procedure TfrmMain.StartAnalysis(const aRoots: TArray<string>);
var
  lRequest: TRepositoryOperationRequest;
  lError: string;
begin
  if RepositoryJobBlocked or (Length(aRoots) = 0) then
    Exit;
  if not ReadSettingsFromUi(lError) then
  begin
    MessageDlg(rsInvalidInput + lError, mtWarning, [mbOK], 0);
    Exit;
  end;
  fSettings.Save;
  lRequest := Default(TRepositoryOperationRequest);
  lRequest.Kind := TRepositoryOperationKind.rokAnalysis;
  lRequest.Analysis.RepoRoots := Copy(aRoots);
  lRequest.Analysis.CacheTtlSeconds := fSettings.CacheTtlSeconds;
  lRequest.Analysis.ThrottleLimit := fSettings.ThrottleLimit;
  lRequest.Analysis.DebugLogEnabled := fSettings.DebugLogEnabled;
  StartRepositoryOperation(lRequest);
end;

function TfrmMain.RepositoryJobBlocked: Boolean;
begin
  Result := fShuttingDown or fCacheLoading or (fScanThread <> nil) or
    fBulkActionRunning or (fActionBusyCount > 0) or (fQueue.Count > 0);
end;

function TfrmMain.LoadTraversalPatterns(const aPath: string;
  const aDefaults: TArray<string>): TArray<TIgnorePattern>;
var
  lPattern: string;
  lHash, lCount: Integer;
  i: Integer;
begin
  if FileExists(aPath) then
    Exit(LoadIgnorePatterns(aPath));
  SetLength(Result, Length(aDefaults));
  lCount := 0;
  for i := 0 to High(aDefaults) do
  begin
    lPattern := aDefaults[i];
    lHash := lPattern.IndexOf('#');
    if lHash >= 0 then
      SetLength(lPattern, lHash);
    lPattern := NormalizePathForMatch(lPattern.Trim);
    if lPattern = '' then
      Continue;
    Result[lCount].Pattern := lPattern;
    Result[lCount].Raw := aDefaults[i];
    Result[lCount].HasSlash := lPattern.Contains('/');
    Result[lCount].IsAbsolute := lPattern.StartsWith('//') or
      ((Length(lPattern) >= 3) and (lPattern[2] = ':') and (lPattern[3] = '/'));
    Inc(lCount);
  end;
  SetLength(Result, lCount);
end;

procedure TfrmMain.StartRepositoryOperation(const aRequest: TRepositoryOperationRequest);
var
  lRequest: TRepositoryOperationRequest;
  lGeneration: Int64;
  lCancelToken: iCancelToken;
begin
  if RepositoryJobBlocked then
    Exit;
  lRequest := aRequest;
  lRequest.Discovery.Roots := Copy(aRequest.Discovery.Roots);
  lRequest.Discovery.Rules := Copy(aRequest.Discovery.Rules);
  lRequest.Analysis.RepoRoots := Copy(aRequest.Analysis.RepoRoots);
  lRequest.DefaultIgnoreDirs := Copy(aRequest.DefaultIgnoreDirs);
  Inc(fScanGeneration);
  lGeneration := fScanGeneration;
  fOperationTerminalReceived := False;
  if lRequest.Kind = TRepositoryOperationKind.rokDiscovery then
    fOperationCaption := rsScanActivity
  else
    fOperationCaption := rsAnalyzeActivity;
  fMaxUiBatchMilliseconds := 0;
  fUiMetricsPending := True;
  fQueue.ResetPeakCount;
  lCancelToken := TCancelToken.Create;
  fCancelToken := lCancelToken;
  SetScanningState(True);
  UpdateStatusText(fOperationCaption);
  pbProgress.Visible := True;
  pbProgress.Style := pbstMarquee;
  QueueLog(cLogScanStarted);
  fScanThread := TThread.CreateAnonymousThread(
    procedure
    var
      lWorkRequest: TRepositoryOperationRequest;
      lErrEvent: TUiEvent;
    begin
      lWorkRequest := lRequest;
      try
        if lWorkRequest.Kind = TRepositoryOperationKind.rokDiscovery then
        begin
          lWorkRequest.Discovery.IgnorePatterns := LoadTraversalPatterns(lWorkRequest.IgnorePath,
            lWorkRequest.DefaultIgnoreDirs);
          fScanner.DiscoverRepositories(lWorkRequest.Discovery, fQueue, lCancelToken, lGeneration);
        end else
          fScanner.AnalyzeRepositories(lWorkRequest.Analysis, fQueue, lCancelToken, lGeneration);
      except
        on E: Exception do
        begin
          lErrEvent := Default(TUiEvent);
          if lWorkRequest.Kind = TRepositoryOperationKind.rokDiscovery then
            lErrEvent.Kind := TUiEventKind.uekDiscoveryFinished
          else
            lErrEvent.Kind := TUiEventKind.uekAnalysisFinished;
          lErrEvent.Generation := lGeneration;
          lErrEvent.OperationError := E.ClassName + ': ' + E.Message;
          lErrEvent.OperationCancelled := lCancelToken.Canceled;
          lErrEvent.RepoRoots := fScanner.Cache.GetInventory;
          fQueue.Enqueue(lErrEvent);
        end;
      end;
    end
  );
  fScanThread.FreeOnTerminate := False;
  fScanThread.Start;
  UpdateBulkActionButtons;
end;

procedure TfrmMain.ReconcileRepositoryInventory(const aRoots: TArray<string>);
var
  g: TGarbos;
  lKeep: TDictionary<string, Boolean>;
  lRoot, lSelectedRoot: string;
begin
  if fRepoViewDirty then
    lSelectedRoot := fRepoViewSelectionRoot
  else
    lSelectedRoot := SelectedRepoRoot;
  GC(lKeep, TDictionary<string, Boolean>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase), g);
  for lRoot in aRoots do
    lKeep.AddOrSetValue(lRoot, True);
  for lRoot in fRepoStatusMap.Keys.ToArray do
    if not lKeep.ContainsKey(lRoot) then
      fRepoStatusMap.Remove(lRoot);
  fRepoListModel.ReconcileInventory(aRoots);
  fRepoViewDirty := False;
  fRepoViewSelectionRoot := '';
  RefreshRepoTree(lSelectedRoot);
  UpdateBulkActionButtons;
  UpdateStatusFilterItems;
end;

procedure TfrmMain.HandleRepositoryOperationFinished(const aEvent: TUiEvent);
var
  lOperationName, lText: string;
begin
  if aEvent.Kind = TUiEventKind.uekDiscoveryFinished then
    lOperationName := rsDiscoveryOperation
  else
    lOperationName := rsAnalysisOperation;
  if aEvent.OperationCancelled then
    lText := Format(rsOperationCancelled, [lOperationName])
  else if not aEvent.OperationSucceeded then
    lText := Format(rsOperationFailed, [lOperationName, aEvent.OperationError])
  else if aEvent.Kind = TUiEventKind.uekDiscoveryFinished then
    lText := Format(rsDiscoveryComplete, [aEvent.ScanSummary.DiscoveredCount, fRepoListModel.VisibleCount])
  else
    lText := Format(rsAnalysisComplete, [aEvent.ScanSummary.RepoCount, aEvent.ScanSummary.CandidateCount]);
  memLog.Lines.Add(lText);
  UpdateStatusText(lText);
  pbProgress.Visible := False;
  pbProgress.Position := 0;
  fOperationTerminalReceived := True;
  UpdateStatusFilterItems;
end;

procedure TfrmMain.FinishRepositoryOperation;
begin
  if (fScanThread = nil) or not fOperationTerminalReceived or not fScanThread.Finished then
    Exit;
  FreeAndNil(fScanThread);
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
  lDisplayText, lObservation: string;
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

  procedure DrawAction(const aRect: TRect; const aImageIndex, aButtonIndex: Integer);
  var
    lImageRect: TRect;
    lHot: Boolean;
  begin
    if IsRectEmpty(aRect) then
      Exit;
    lHot := (fHotRepoNode = aNode) and (fHotRepoButton = aButtonIndex);
    if lHot then
    begin
      aTargetCanvas.Brush.Color := clBtnFace;
      aTargetCanvas.Pen.Color := clHighlight;
    end else begin
      aTargetCanvas.Brush.Color := clWindow;
      aTargetCanvas.Pen.Color := $00D0D0D0;
    end;
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
    lDisplayText := lItem.DisplayPath;
    lObservation := BuildObservationText(lItem.Status);
    if lObservation <> '' then
      lDisplayText := lDisplayText + '  ' + lObservation;
    DrawText(aTargetCanvas.Handle, PChar(lDisplayText), -1, lTextRect,
      DT_END_ELLIPSIS or DT_NOPREFIX or DT_SINGLELINE or DT_VCENTER);

    aTargetCanvas.Font.Assign(Font);
    aTargetCanvas.Font.Height := -13;
    aTargetCanvas.Font.Style := [];
    lBadgeX := aCellRect.Left + 16;
    lBadgeRight := lTextRect.Right;
    if lItem.State = TRepoListItemState.rlisWaiting then
      DrawBadge(rsStatusWaiting, False)
    else begin
      if Trim(lItem.Status.LastPullError) <> '' then
        DrawBadge(rsBadgePullFailed, True);
      if Trim(lItem.Status.LastPushError) <> '' then
        DrawBadge(rsBadgePushFailed, True);
      if lItem.Status.ScanFailed then
        DrawBadge(rsBadgeScanFailed, True)
      else begin
        DrawBadge(rsBadgeBranch + lItem.Status.Branch, False);
        if lItem.Status.FetchFailed then
          DrawBadge(rsBadgeFetchFailed, True)
        else if not lItem.Status.HasOrigin then
          DrawBadge(rsBadgeNoOrigin, True)
        else if lItem.Status.Upstream = '' then
          DrawBadge(rsBadgeNoUpstream, True)
        else if lItem.Status.UnrelatedHistory then
          DrawBadge(rsBadgeUnrelatedHistory, True)
        else if lItem.Status.IsOutOfDate then
          DrawBadge(rsBadgeBehind + IntToStr(lItem.Status.Behind), True)
        else if lItem.Status.HasUnpushed then
          DrawBadge(rsBadgeAhead + IntToStr(lItem.Status.Ahead), True)
        else
          DrawBadge(rsBadgeSyncOk, False);
        if lItem.Status.SubmoduleNeedsMainFastForward and
          (not lItem.Status.UnrelatedHistory) then
          DrawBadge(rsBadgeSubmoduleNoFastForward + lItem.Status.SubmoduleMainRemoteRef, True);
        if lItem.Status.IsDirty then
        begin
          lDirty := BuildDirtyBadge(lItem.Status.DirtySummary, lHasFiles);
          DrawBadge(lDirty, True);
        end;
      end;
    end;

    DrawAction(lPullRect, 1, 1);
    DrawAction(lPushRect, 2, 2);
    if (fHotRepoNode = aNode) and (fHotRepoButton = 3) then
    begin
      aTargetCanvas.Brush.Color := clBtnFace;
      aTargetCanvas.Pen.Color := clHighlight;
    end else begin
      aTargetCanvas.Brush.Color := clWindow;
      aTargetCanvas.Pen.Color := $00D0D0D0;
    end;
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

procedure TfrmMain.SetRepoHotButton(const aNode: PVirtualNode; const aButtonIndex: Integer);
var
  lOldNode: PVirtualNode;
begin
  if (fHotRepoNode = aNode) and (fHotRepoButton = aButtonIndex) then
    Exit;
  lOldNode := fHotRepoNode;
  fHotRepoNode := aNode;
  fHotRepoButton := aButtonIndex;
  if lOldNode <> nil then
    RepoTree.InvalidateNode(lOldNode);
  if aNode <> nil then
    RepoTree.InvalidateNode(aNode);
  if aButtonIndex = 0 then
    RepoTree.Cursor := crDefault
  else
    RepoTree.Cursor := crHandPoint;
end;

procedure TfrmMain.RepoTreeKeyDown(aSender: TObject; var aKey: Word; aShift: TShiftState);
var
  lRepoRoot: string;
begin
  if (aKey <> Ord('C')) or (not (ssCtrl in aShift)) then
    Exit;
  lRepoRoot := SelectedRepoRoot;
  if lRepoRoot = '' then
    Exit;
  CopyTextToClipboard(lRepoRoot);
  aKey := 0;
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

procedure TfrmMain.RepoTreeMouseLeave(aSender: TObject);
begin
  SetRepoHotButton(nil, 0);
end;

procedure TfrmMain.RepoTreeMouseMove(aSender: TObject; aShift: TShiftState; X, Y: Integer);
var
  lNode: PVirtualNode;
  lItem: TRepoListItem;
  lCellRect: TRect;
  lPullRect: TRect;
  lPushRect: TRect;
  lMoreRect: TRect;
  lPoint: TPoint;
  lButtonIndex: Integer;
begin
  lNode := RepoTree.GetNodeAt(X, Y);
  lButtonIndex := 0;
  if RepoItemForNode(lNode, lItem) then
  begin
    lCellRect := RepoTree.GetDisplayRect(lNode, 0, False);
    GetRepoActionRects(lItem, lCellRect, lPullRect, lPushRect, lMoreRect);
    lPoint := Point(X, Y);
    if PtInRect(lPullRect, lPoint) then
      lButtonIndex := 1
    else if PtInRect(lPushRect, lPoint) then
      lButtonIndex := 2
    else if PtInRect(lMoreRect, lPoint) then
      lButtonIndex := 3;
  end;
  if lButtonIndex = 0 then
    lNode := nil;
  SetRepoHotButton(lNode, lButtonIndex);
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
  lStatus: TRepoStatus;
begin
  if fPopupRepoRoot = '' then
    Exit;
  if (Sender = miRepoTortoiseCommit) or (Sender = miRepoTortoiseSync) then
  begin
    if fCacheLoading or (not fRepoStatusMap.TryGetValue(fPopupRepoRoot, lStatus)) or
      lStatus.IsCached or lStatus.ScanFailed then
    begin
      UpdateStatusText(rsAnalysisRequired);
      Exit;
    end;
  end;
  if Sender = miRepoLastPullError then
  begin
    if fRepoStatusMap.TryGetValue(fPopupRepoRoot, lStatus) then
      TfrmTextDetailsDialog.ShowDetails(rsLastPullErrorTitle, lStatus.LastPullError);
    Exit;
  end else if Sender = miRepoLastPushError then
  begin
    if fRepoStatusMap.TryGetValue(fPopupRepoRoot, lStatus) then
      TfrmTextDetailsDialog.ShowDetails(rsLastPushErrorTitle, lStatus.LastPushError);
    Exit;
  end else if Sender = miRepoLastScanError then
  begin
    if fRepoStatusMap.TryGetValue(fPopupRepoRoot, lStatus) then
      ShowImmediateActionError(rsLastScanErrorTitle, lStatus.ScanError);
    Exit;
  end else if Sender = miRepoTortoiseCommit then
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
  end else if Sender = miRepoTortoiseLog then
  begin
    if not TTortoiseGit.TryLaunch(fTortoiseGitExe, TTortoiseGitCommand.tgcLog,
      fPopupRepoRoot, lError) then
      MessageDlg(lError, mtError, [mbOK], 0);
    Exit;
  end else if Sender = miRepoCommit then
    lAction := TRepoAction.raCommit
  else if Sender = miRepoFetch then
    lAction := TRepoAction.raFetch
  else if Sender = miRepoPull then
    lAction := TRepoAction.raPull
  else if Sender = miRepoPush then
    lAction := TRepoAction.raPush
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
  if (aAction <> TRepoAction.raOpenFolder) and RepositoryJobBlocked then
    Exit;
  if aAction = TRepoAction.raRescan then
  begin
    StartAnalysis([aRepoRoot]);
    Exit;
  end;
  if aAction in [TRepoAction.raPull, TRepoAction.raCommit, TRepoAction.raPush,
    TRepoAction.raFixSubmoduleMain] then
  begin
    if (not fRepoStatusMap.TryGetValue(aRepoRoot, lStatus)) or lStatus.IsCached or lStatus.ScanFailed then
    begin
      UpdateStatusText(rsAnalysisRequired);
      Exit;
    end;
  end;
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

function TfrmMain.BuildRepoActionRequest(const aAction: TRepoAction; const aRepoRoot,
  aMessage: string): TRepoActionRequest;
var
  lExisting: TRepoStatus;
  lParentExisting: TRepoStatus;
  lSlashPos: Integer;
begin
  Result := Default(TRepoActionRequest);
  Result.Action := aAction;
  Result.RepoRoot := aRepoRoot;
  Result.MessageText := aMessage;
  case aAction of
    TRepoAction.raPull: Result.ActionName := rsPull;
    TRepoAction.raCommit: Result.ActionName := rsCommit;
    TRepoAction.raPush: Result.ActionName := rsPush;
    TRepoAction.raFetch: Result.ActionName := rsFetch;
    TRepoAction.raFixSubmoduleMain: Result.ActionName := rsFixSubmoduleMain;
    TRepoAction.raRescan: Result.ActionName := rsRescanAction;
  else
    Result.ActionName := rsOpenFolder;
  end;

  if fRepoStatusMap.TryGetValue(aRepoRoot, lExisting) then
  begin
    Result.MatchedFolders := lExisting.MatchedFolders;
    if (aAction in [TRepoAction.raPull, TRepoAction.raPush]) and lExisting.IsSubmodule and
      (lExisting.SuperprojectRoot <> '') and
      fRepoStatusMap.TryGetValue(lExisting.SuperprojectRoot, lParentExisting) then
    begin
      Result.ParentRepoRoot := lParentExisting.RepoRoot;
      Result.ParentMatchedFolders := lParentExisting.MatchedFolders;
    end;
    if lExisting.Upstream <> '' then
    begin
      lSlashPos := lExisting.Upstream.IndexOf('/');
      if lSlashPos > 0 then
        Result.FetchRemote := lExisting.Upstream.Substring(0, lSlashPos);
    end;
  end;
  if Result.FetchRemote = '' then
    Result.FetchRemote := 'origin';
end;

procedure TfrmMain.PerformRepoAction(const aRequest: TRepoActionRequest);
var
  lErr: string;
  lEvent: TUiEvent;
  lMsg: string;
  lOk: Boolean;
  lParentStatus: TRepoStatus;
  lParentStatusErr: string;
  lParentStatusOk: Boolean;
  lScanner: TRepoScanner;
  lStatus: TRepoStatus;
  lStatusErr: string;
  lStatusOk: Boolean;
begin
  if aRequest.Action in [TRepoAction.raPull, TRepoAction.raCommit, TRepoAction.raPush,
    TRepoAction.raFixSubmoduleMain] then
  begin
    if (not fScanner.Cache.TryGetStatus(aRequest.RepoRoot, lStatus)) or
      lStatus.IsCached or lStatus.ScanFailed then
    begin
      lEvent := Default(TUiEvent);
      lEvent.Kind := TUiEventKind.uekActionResult;
      lEvent.RepoRoot := aRequest.RepoRoot;
      lEvent.ActionTag := Ord(aRequest.Action);
      lEvent.ActionIsBulk := aRequest.IsBulk;
      lEvent.ActionSucceeded := False;
      lEvent.ActionError := rsAnalysisRequired;
      lEvent.Text := aRequest.ActionName + ': ' + rsAnalysisRequired;
      fQueue.Enqueue(lEvent);
      Exit;
    end;
  end;
  try
    lErr := '';
    lOk := False;
    case aRequest.Action of
      TRepoAction.raPull: lOk := fGit.TryPull(aRequest.RepoRoot, lErr);
      TRepoAction.raCommit: lOk := fGit.TryCommit(aRequest.RepoRoot,
        aRequest.MessageText, lErr);
      TRepoAction.raPush: lOk := fGit.TryPush(aRequest.RepoRoot, lErr);
      TRepoAction.raFetch: lOk := fGit.TryFetchRemote(aRequest.RepoRoot,
        aRequest.FetchRemote, 60000, lErr);
      TRepoAction.raFixSubmoduleMain: lOk := fGit.TryFixSubmoduleFastForwardToMain(
        aRequest.RepoRoot, aRequest.MessageText, lErr);
      TRepoAction.raRescan: lOk := True;
    end;

    if lOk then
      lMsg := Format('%s %s: %s', [cLogAction, aRequest.ActionName, cLogActionOk])
    else
      lMsg := Format('%s %s: %s - %s', [cLogAction, aRequest.ActionName,
        cLogActionFailed, lErr]);
  except
    on E: Exception do
    begin
      lErr := E.Message;
      lOk := False;
      lMsg := Format('%s %s: %s - %s', [cLogAction, aRequest.ActionName,
        cLogActionFailed, E.Message]);
    end;
  end;

  lStatusOk := False;
  lStatus := Default(TRepoStatus);
  lStatusErr := '';
  lParentStatusOk := False;
  lParentStatus := Default(TRepoStatus);
  lParentStatusErr := '';
  try
    lScanner := TRepoScanner.Create(fGit, fScanner.Cache, fCacheFilePath);
    try
      try
        lStatusOk := lScanner.TryRefreshRepoStatus(fSettings, aRequest.RepoRoot,
          aRequest.MatchedFolders, lStatus, lStatusErr);
      except
        on E: Exception do
          lStatusErr := E.Message;
      end;
      if aRequest.ParentRepoRoot <> '' then
      begin
        try
          lParentStatusOk := lScanner.TryRefreshRepoStatus(fSettings,
            aRequest.ParentRepoRoot, aRequest.ParentMatchedFolders, lParentStatus,
            lParentStatusErr);
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

  if aRequest.Action = TRepoAction.raRescan then
  begin
    lOk := lStatusOk;
    lErr := lStatusErr;
    if lOk then
      lMsg := Format('%s %s: %s', [cLogAction, aRequest.ActionName, cLogActionOk])
    else
      lMsg := Format('%s %s: %s - %s', [cLogAction, aRequest.ActionName,
        cLogActionFailed, lErr]);
  end;

  if lStatusOk and (lStatusErr <> '') then
    lMsg := lMsg + ' | ' + lStatusErr;
  if lParentStatusOk and (lParentStatusErr <> '') then
    lMsg := lMsg + ' | ' + lParentStatusErr;

  if (aRequest.ParentRepoRoot <> '') and (not lParentStatusOk) then
    lMsg := lMsg + ' | ' + Format(cLogParentRefreshFailed, [lParentStatusErr]);

  if fShuttingDown then
    Exit;

  lEvent := Default(TUiEvent);
  lEvent.Kind := TUiEventKind.uekActionResult;
  lEvent.Text := lMsg;
  lEvent.RepoRoot := aRequest.RepoRoot;
  lEvent.ActionTag := Ord(aRequest.Action);
  lEvent.ActionIsBulk := aRequest.IsBulk;
  lEvent.ActionSucceeded := lOk;
  lEvent.ActionError := lErr;
  if lStatusOk or ((aRequest.RepoRoot <> '') and lStatus.ScanFailed) then
    lEvent.RepoStatus := lStatus;
  if lParentStatusOk or ((aRequest.ParentRepoRoot <> '') and lParentStatus.ScanFailed) then
    lEvent.RelatedRepoStatus := lParentStatus;
  fQueue.Enqueue(lEvent);
end;

procedure TfrmMain.RunRepoAction(const aAction: TRepoAction; const aRepoRoot: string;
  const aMessage: string);
var
  lRequest: TRepoActionRequest;
  lThread: TThread;
begin
  if RepositoryJobBlocked then
    Exit;
  CleanupFinishedActionThreads;
  lRequest := BuildRepoActionRequest(aAction, aRepoRoot, aMessage);

  BeginActionBusy;
  try
    lThread := TThread.CreateAnonymousThread(
      procedure
      begin
        PerformRepoAction(lRequest);
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
  if RepositoryJobBlocked then
    Exit;
  if not ReadSettingsFromUi(lErr) then
  begin
    MessageDlg(rsInvalidInput + lErr, mtWarning, [mbOK], 0);
    Exit;
  end;
  fSettings.Save;
  StartScan;
end;

procedure TfrmMain.btnAnalyzeReposClick(aSender: TObject);
begin
  StartAnalysis(fRepoListModel.VisibleRoots);
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

procedure TfrmMain.btnBrowseStartClick(Sender: TObject);
begin
  TfrmScanPathsDialog.ExecuteTraversalOptions(Self, ResolveIgnoreDirsPath,
    fSettings.ExcludeDirs);
end;

procedure TfrmMain.btnFilterHelpClick(Sender: TObject);
begin
  MessageBox(Handle, PChar(rsFilterHelp), PChar(rsFilterHelpTitle), MB_OK or MB_ICONINFORMATION);
end;

procedure TfrmMain.btnStatusFilterHelpClick(Sender: TObject);
var
  g: TGarbos;
  lDialog: TfrmStatusFilterHelp;
begin
  GC(lDialog, TfrmStatusFilterHelp.Create(nil), g);
  lDialog.ShowModal;
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
  FinishRepositoryOperation;
  UpdateBulkActionButtons;
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
