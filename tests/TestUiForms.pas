unit TestUiForms;

interface

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.IOUtils, System.SyncObjs, System.SysUtils, System.Types,
  System.UITypes,
  Winapi.ActiveX, Winapi.OleAcc, Winapi.Windows,
  Vcl.Buttons, Vcl.Clipbrd, Vcl.ComCtrls, Vcl.Controls, Vcl.Forms, Vcl.Menus, Vcl.StdCtrls,
  Vcl.VirtualImageList,
  VirtualTrees.Types,
  DUnitX.TestFramework,
  UAppSettings, UFolderSelection, UFolderTreeFrame, UGitClient, UMainForm, UModels, URepoCache, URepoListModel, UScanPathsDialog, UTortoiseGit, UUiEventQueue;

type
  TFolderTreeAccess = class(TFolderTreeFrame);

  TTestMainForm = class(TfrmMain)
  protected
    function RepositoryCachePath: string; override;
  public
    class var CachePathForTest: string;
  public
    fBulkSummaryCount: Integer;
    fImmediateErrorCount: Integer;
    fLastDialogCaption: string;
    fLastDialogText: string;
    procedure AddRepoForTest(const aRepoRoot: string);
    procedure ApplyExclusionsForTest(const aPatterns: TArray<string>);
    function SelectedRootForTest: string;
    function SharedCacheForTest: TRepoCache;
    function HasMutationGlyphForTest(const aStatus: TRepoStatus): Boolean;
    procedure PerformActionForTest(const aRequest: TRepoActionRequest);
    procedure AddStatusForTest(const aStatus: TRepoStatus);
    procedure HandleEventForTest(const aEvent: TUiEvent);
    procedure SetSearchFilterCounts(const aMatchedCount, aDiscoveredCount: Integer;
      const aHasCounts: Boolean);
    procedure ShowBulkActionSummary(const aCaption, aText: string); override;
    procedure ShowImmediateActionError(const aCaption, aText: string); override;
  end;

  TTestScanPathsDialog = class(TfrmScanPathsDialog)
  public
    procedure SendKey(const aKey: Word);
    procedure SetIgnorePath(const aPath: string);
  end;

  [TestFixture]
  TUiFormTests = class
  private
    fSettingsBytes: TBytes;
    fSettingsExisted: Boolean;
    function ReadClipboardText: string;
    function RunFixtureGit(const aGit: TGitClient; const aRepo: string;
      const aArgs: TArray<string>): string;
  public
    [Setup]
    procedure PreserveSettings;
    [TearDown]
    procedure RestoreSettings;
    [Test]
    procedure Toolbar_ScanIsLeftmostAction;
    [Test]
    procedure RepositoryCommands_SeparateDiscoveryFromAnalysis;
    [TestCase('Cancelled', 'True')]
    [TestCase('Completed', 'False')]
    procedure DiscoveryEvents_PreserveSnapshotsAndReconcileMembership(const aCancelled: Boolean);
    [TestCase('Cancelled', 'True')]
    [TestCase('Completed', 'False')]
    procedure DiscoveryEvents_PreserveSelectedRootAcrossInsertionsAndTerminal(const aCancelled: Boolean);
    [TestCase('Search', '0')]
    [TestCase('Folders', '1')]
    [TestCase('Status', '2')]
    [TestCase('Exclusions', '3')]
    [TestCase('Clear filters', '4')]
    procedure Filters_PreserveSelectedRootWhileDiscoveryRefreshIsPending(const aFilter: Integer);
    [Test]
    procedure Analysis_CapturesVisibleCachedAndWaitingRootsBeforeFilterChanges;
    [Test]
    procedure FolderContext_DiscoveryKeepsUncheckedResultsHiddenAndPreservesRules;
    [Test]
    procedure Toolbar_AllActionsHaveDistinctSvgImages;
    [Test]
    procedure AllApplicationButtons_UseBitBtn;
    [Test]
    procedure ScanActivity_UsesSkillSearchAnimatedControl;
    [Test]
    procedure BulkActivity_ShowsProgressStatusAndAnimation;
    [Test]
    procedure StatusBar_NativeBottomLeftLookupExposesCompletion;
    [Test]
    procedure ScanPathsDialog_EscapeCancels;
    [Test]
    procedure ScanPathsDialog_CombinesScanAndIgnoredPaths;
    [Test]
    procedure ScanPathsDialog_SavePersistsIgnoreRules;
    [Test]
    procedure SearchFilter_HasMnemonicAndHelpButton;
    [Test]
    procedure SearchFilter_ProjectsKnownRowsImmediately;
    [Test]
    procedure SearchFilter_SurvivesRestartWithoutStartingWork;
    [Test]
    procedure Exclusions_ApplyToKnownRowsAndPersist;
    [Test]
    procedure Filters_KeepCountsCurrentAfterResultsAndCompletion;
    [Test]
    procedure StatusFilter_SurvivesRestart;
    [TestCase('Negative', '-1')]
    [TestCase('Past end', '999')]
    procedure StatusFilter_InvalidSavedIndexUsesAttention(const aIndex: Integer);
    [Test]
    procedure Filters_ExplainEmptyResultsAndCanBeCleared;
    [Test]
    procedure Folders_ProjectCachedRowsAndKeepJobsIdle;
    [Test]
    procedure Folders_PersistEmptySelectionAndPaneWidth;
    [Test]
    procedure Folders_MnemonicKeepsSearchShortcutUnambiguous;
    [Test]
    procedure TraversalOptions_HidesPathEditorAndSavesIgnores;
    [Test]
    procedure SearchFilter_ShowsMatchedAndDiscoveredCounts;
    [Test]
    procedure StatusFilter_OffersActionableStatesAndHelp;
    [Test]
    procedure StatusFilterHelp_IsModalReadyAndExplainsEveryState;
    [Test]
    procedure BulkActions_ExplainVisibleScopeWithBalloonHints;
    [Test]
    procedure Settings_SeparatesScanAndActionThreadLimits;
    [Test]
    procedure RepositoryView_WiresHoverAndCopiesSelectedPath;
    [Test]
    procedure RepositoryAccessibilityText_DescribesFailureStates;
    [TestCase('Waiting', 'False')]
    [TestCase('Cached', 'True')]
    procedure RepositoryAccessibilityText_OmitsAbsolutePath(const aCached: Boolean);
    [TestCase('Minutes', '0')]
    [TestCase('Hours', '1')]
    [TestCase('Days', '2')]
    [TestCase('Months', '3')]
    [TestCase('Years', '4')]
    [TestCase('One minute', '5')]
    [TestCase('One hour', '6')]
    [TestCase('One day', '7')]
    [TestCase('One month', '8')]
    [TestCase('One year', '9')]
    [TestCase('Just now', '10')]
    procedure RepositoryAccessibilityText_UsesRelativeAge(const aMode: Integer);
    [Test]
    procedure RepositoryAccessibilityText_DescribesUnrelatedHistory;
    [Test]
    procedure RepositoryPopup_OffersTortoiseGitLogWhenInstalled;
    [Test]
    procedure RepositoryPopup_OffersPullAndPushForEligibleRow;
    [Test]
    procedure RepositoryPopup_OffersLastOperationErrors;
    [Test]
    procedure RepositoryPopup_ShowsFullScanErrorAndRecoveryPreservesActionError;
    [Test]
    procedure DetailsDialog_IsScrollableCopyableAndEscapeCloseable;
    [Test]
    procedure DialogButtons_UseSharedSvgGlyphs;
    [Test]
    procedure BulkActionFailures_AreSummarizedWithoutIntermediateDialogs;
    [Test]
    procedure ActionFailureState_PersistsAcrossRescanAndClearsIndependently;
    [Test]
    procedure SingleActionFailure_ShowsImmediateDialog;
    [Test]
    procedure RepositoryView_UsesVirtualStringTree;
    [TestCase('Cached', 'True,False')]
    [TestCase('Failed', 'False,True')]
    procedure StaleStatus_DisablesMutatingUiActions(const aCached, aFailed: Boolean);
    [Test]
    procedure Startup_RestoresUnavailableCachedAndUnanalyzedRepositories;
    [Test]
    procedure Startup_ReportsAndPreservesCorruptCache;
    [Test]
    procedure Startup_DisablesActionsBeforeCompletion;
    [TestCase('Cached mutation', '0')]
    [TestCase('Failed mutation', '1')]
    [TestCase('Shared refresh', '2')]
    [TestCase('Fresh mutation', '3')]
    [TestCase('Cache write warning', '4')]
    procedure ActionWorker_UsesSharedObservation(const aMode: Integer);
    [TestCase('Fresh', '0')]
    [TestCase('Cached', '1')]
    [TestCase('Failed', '2')]
    procedure InlineActions_RequireFreshStatus(const aMode: Integer);
    [Test]
    procedure Shutdown_FlushesPendingObservation;
  end;

implementation

uses
  AutoFree;

procedure TUiFormTests.StatusBar_NativeBottomLeftLookupExposesCompletion;
const
  cCompletionText = 'Analysis completed: 1 of 1 repositories.';
var
  g: TGarbos;
  lForm: TTestMainForm;
  lClient, lStatus: IAccessible;
  lName: WideString;
  lLeft, lTop, lWidth, lHeight: Integer;
  lStatusLeft, lStatusTop, lStatusWidth, lStatusHeight: Integer;
  lPoint: TPoint;
  lForeground: HWND;
  lEvent: TUiEvent;
begin
  lForeground := GetForegroundWindow;
  GC(lForm, TTestMainForm.Create(nil), g);
  lForm.HandleNeeded;
  lForm.stsMain.HandleNeeded;
  lEvent := Default(TUiEvent);
  lEvent.Kind := TUiEventKind.uekLog;
  lEvent.Text := cCompletionText;
  lForm.HandleEventForTest(lEvent);
  Assert.AreEqual(Integer(S_OK), Integer(AccessibleObjectFromWindow(lForm.Handle,
    DWORD(OBJID_CLIENT), IID_IAccessible, lClient)));
  Assert.AreEqual(Integer(S_OK), Integer(lClient.accLocation(lLeft, lTop, lWidth, lHeight, CHILDID_SELF)));
  Assert.IsTrue((lWidth > 0) and (lHeight > 0));
  // NVDA derives this point from foreground OBJID_CLIENT, independently of status-bar layout.
  // The companion external probe verifies actual desktop hit testing against the running app.
  lPoint := Point(lLeft, lTop + lHeight - 1);
  Assert.AreEqual(Integer(S_OK), Integer(AccessibleObjectFromWindow(lForm.stsMain.Handle,
    DWORD(OBJID_CLIENT), IID_IAccessible, lStatus)));
  Assert.AreEqual(Integer(S_OK), Integer(lStatus.accLocation(lStatusLeft, lStatusTop,
    lStatusWidth, lStatusHeight, CHILDID_SELF)));
  Assert.IsTrue(PtInRect(Rect(lStatusLeft, lStatusTop, lStatusLeft + lStatusWidth,
    lStatusTop + lStatusHeight), lPoint),
    'Native status bounds must contain the foreground client bottom-left lookup point');
  Assert.AreEqual(Integer(S_OK), Integer(lStatus.Get_accName(1, lName)));
  Assert.AreEqual(cCompletionText, string(lName), 'Native status child must expose the latest completion');
  Assert.AreEqual(NativeUInt(lForeground), NativeUInt(GetForegroundWindow),
    'Status lookup must leave keyboard focus unchanged');
end;
procedure TUiFormTests.TraversalOptions_HidesPathEditorAndSavesIgnores;
var
  lDialog: TTestScanPathsDialog;
  lPath: string;
begin
  lPath := TPath.Combine(TPath.GetTempPath, 'RepoPulse-ignore-' + TPath.GetRandomFileName);
  lDialog := TTestScanPathsDialog.Create(nil);
  try
    lDialog.SetIgnorePath(lPath);
    lDialog.memPaths.Text := TPath.GetTempPath;
    lDialog.ConfigureTraversalOnly;
    Assert.IsFalse(lDialog.pnlScanPaths.Visible, 'Folder selection belongs to the checkbox tree');
    Assert.IsFalse(lDialog.btnAddFolder.Visible);
    Assert.IsTrue(lDialog.pnlIgnorePaths.Visible);
    lDialog.memIgnorePaths.Text := '.git' + sLineBreak + 'bin';
    lDialog.btnOkClick(nil);
    Assert.AreEqual(Integer(mrOk), lDialog.ModalResult);
    Assert.IsTrue(TFile.ReadAllText(lPath, TEncoding.UTF8).Contains('bin'));
  finally
    lDialog.Free;
    if TFile.Exists(lPath) then
      TFile.Delete(lPath);
  end;
end;

procedure TUiFormTests.Folders_MnemonicKeepsSearchShortcutUnambiguous;
var
  g: TGarbos;
  lForm: TTestMainForm;
  lFolderMnemonic: string;
begin
  GC(lForm, TTestMainForm.Create(nil), g);
  lFolderMnemonic := GetHotkey(lForm.FolderPane.HeadingText.Caption);
  Assert.AreEqual(1, Length(lFolderMnemonic), 'Folder navigation needs an accelerator');
  Assert.AreSame(lForm.FolderPane.FolderTree, lForm.FolderPane.HeadingText.FocusControl,
    'The folder accelerator must target the native folder tree');
  Assert.IsFalse(SameText(lFolderMnemonic, GetHotkey(lForm.lblTargetName.Caption)),
    'Folder navigation must not compete with the existing search accelerator');
  Assert.IsFalse(SameText(lFolderMnemonic, GetHotkey(lForm.btnBrowseStart.Caption)),
    'Folder navigation must not compete with traversal options when Settings is open');
end;

procedure TUiFormTests.Folders_ProjectCachedRowsAndKeepJobsIdle;
var
  lSettings: TAppSettings;
  lRules: TArray<TFolderSelectionRule>;
  lForm: TTestMainForm;
  lFolders: TFolderTreeFrame;
  lNode: TTreeNode;
  lScanCaption: string;
begin
  SetLength(lRules, 1);
  lRules[0].Path := 'C:\RepoPulseFixture';
  lRules[0].Included := True;
  lSettings := TAppSettings.Create;
  try
    lSettings.FolderSelectionRules := lRules;
    lSettings.StatusFilterIndex := Ord(TRepoFilter.rfAll);
    lSettings.Save;
  finally
    lSettings.Free;
  end;
  lForm := TTestMainForm.Create(nil);
  try
    Assert.IsNotNull(lForm.FindComponent('FolderPane'), 'Main form must host the folder tree');
    Assert.IsNull(lForm.FindComponent('pnlRootField'), 'The old scan-path field is replaced');
    Assert.IsNotNull(lForm.FindComponent('FolderSplitter'));
    lFolders := lForm.FindComponent('FolderPane') as TFolderTreeFrame;
    lForm.AddRepoForTest('C:\RepoPulseFixture\Alpha');
    lForm.AddRepoForTest('C:\RepoPulseFixture2\Hidden');
    Assert.AreEqual(Cardinal(1), lForm.RepoTree.RootNodeCount);
    lScanCaption := lForm.btnScan.Caption;
    lNode := TFolderTreeAccess(lFolders).FindNode('C:\RepoPulseFixture');
    Assert.IsNotNull(lNode);
    lNode.CheckState := TNodeCheckState.ncsUnchecked;
    Assert.AreEqual(Cardinal(0), lForm.RepoTree.RootNodeCount, 'Checkbox changes project cached rows immediately');
    Assert.AreEqual(lScanCaption, string(lForm.btnScan.Caption), 'Checkbox changes must not start a job');
    Assert.IsFalse(lForm.pbProgress.Visible);
    lNode.CheckState := TNodeCheckState.ncsChecked;
    Assert.AreEqual(Cardinal(1), lForm.RepoTree.RootNodeCount, 'Checking restores retained rows');
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.Folders_PersistEmptySelectionAndPaneWidth;
var
  lForm: TTestMainForm;
  lFolders: TFolderTreeFrame;
  lSettings: TAppSettings;
begin
  lSettings := TAppSettings.Create;
  try
    lSettings.FolderSelectionRules := [];
    lSettings.FoldersPaneWidth := 310;
    lSettings.Save;
  finally
    lSettings.Free;
  end;
  lForm := TTestMainForm.Create(nil);
  try
    Assert.IsNotNull(lForm.FindComponent('FolderPane'));
    lFolders := lForm.FindComponent('FolderPane') as TFolderTreeFrame;
    Assert.AreEqual(MulDiv(310, lForm.CurrentPPI, 96), lFolders.Width);
    lForm.AddRepoForTest('C:\RepoPulseFixture\Alpha');
    Assert.AreEqual(Cardinal(0), lForm.RepoTree.RootNodeCount);
    lFolders.Width := MulDiv(340, lForm.CurrentPPI, 96);
  finally
    lForm.Free;
  end;
  lForm := TTestMainForm.Create(nil);
  try
    lFolders := lForm.FindComponent('FolderPane') as TFolderTreeFrame;
    Assert.AreEqual(MulDiv(340, lForm.CurrentPPI, 96), lFolders.Width);
    Assert.AreEqual(0, Length(lFolders.Rules), 'Explicit empty selection must not remigrate old scan paths');
    lForm.AddRepoForTest('C:\RepoPulseFixture\Alpha');
    Assert.AreEqual(Cardinal(0), lForm.RepoTree.RootNodeCount);
  finally
    lForm.Free;
  end;
end;

function TTestMainForm.SelectedRootForTest: string;
begin
  Result := SelectedRepoRoot;
end;

procedure TUiFormTests.Filters_KeepCountsCurrentAfterResultsAndCompletion;
var
  lEvent: TUiEvent;
  lForm: TTestMainForm;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lForm.AddRepoForTest('C:\RepoPulseFixture\Alpha');
    lForm.AddRepoForTest('C:\RepoPulseFixture\Beta');
    lForm.cboTargetName.Text := 'Alpha';
    lForm.cboTargetName.OnChange(lForm.cboTargetName);
    lEvent := Default(TUiEvent);
    lEvent.Kind := TUiEventKind.uekScanFinished;
    lEvent.HasScanSummary := True;
    lEvent.ScanSummary.CandidateCount := 50;
    lEvent.ScanSummary.DiscoveredCount := 100;
    lForm.HandleEventForTest(lEvent);
    Assert.AreEqual('Search &Filter (1 of 2)', string(lForm.lblTargetName.Caption),
      'Job totals must not overwrite current projection counts');
    lForm.AddRepoForTest('C:\RepoPulseFixture\Alpha-next');
    TThread.Sleep(110);
    lForm.tmrUiTimer(nil);
    Assert.AreEqual('Search &Filter (2 of 3)', string(lForm.lblTargetName.Caption));
    lForm.cboStatusFilter.ItemIndex := Ord(TRepoFilter.rfDirty);
    lForm.cboStatusFilterChange(nil);
    Assert.AreEqual('Search &Filter (0 of 3)', string(lForm.lblTargetName.Caption));
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.StatusFilter_SurvivesRestart;
var
  lForm: TTestMainForm;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lForm.cboStatusFilter.ItemIndex := Ord(TRepoFilter.rfDirty);
    lForm.cboStatusFilterChange(nil);
  finally
    lForm.Free;
  end;
  lForm := TTestMainForm.Create(nil);
  try
    Assert.AreEqual(Integer(Ord(TRepoFilter.rfDirty)), lForm.cboStatusFilter.ItemIndex);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.StatusFilter_InvalidSavedIndexUsesAttention(const aIndex: Integer);
var
  lForm: TTestMainForm;
  lSettings: TAppSettings;
begin
  lSettings := TAppSettings.Create;
  try
    lSettings.StatusFilterIndex := aIndex;
    lSettings.Save;
  finally
    lSettings.Free;
  end;
  lForm := TTestMainForm.Create(nil);
  try
    Assert.AreEqual(0, lForm.cboStatusFilter.ItemIndex);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.Filters_ExplainEmptyResultsAndCanBeCleared;
var
  lButton: TBitBtn;
  lForm: TTestMainForm;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lForm.AddRepoForTest('C:\RepoPulseFixture\Alpha');
    lForm.ApplyExclusionsForTest(['Alpha']);
    lForm.cboTargetName.Text := 'missing';
    lForm.cboTargetName.OnChange(lForm.cboTargetName);
    Assert.IsTrue(Pos('No repositories match', lForm.stsMain.SimpleText) > 0);
    lButton := lForm.FindComponent('btnClearFilters') as TBitBtn;
    Assert.IsNotNull(lButton, 'The empty state must offer a clear-filters action');
    lButton.Click;
    Assert.AreEqual(Cardinal(1), lForm.RepoTree.RootNodeCount);
    Assert.AreEqual('', string(lForm.cboTargetName.Text));
    Assert.AreEqual(Integer(Ord(TRepoFilter.rfAll)), lForm.cboStatusFilter.ItemIndex);
    lForm.AddRepoForTest('C:\RepoPulseFixture\Beta');
    lForm.cboTargetName.Text := 'Beta';
    lForm.cboTargetName.OnChange(lForm.cboTargetName);
    lForm.RepoTree.FocusedNode := lForm.RepoTree.GetFirst;
    Assert.AreEqual('C:\RepoPulseFixture\Beta', lForm.SelectedRootForTest);
    lButton.Click;
    Assert.AreEqual('C:\RepoPulseFixture\Beta', lForm.SelectedRootForTest,
      'Clearing filters must preserve selection by root, not old row index');
  finally
    lForm.Free;
  end;
end;

procedure TTestMainForm.ApplyExclusionsForTest(const aPatterns: TArray<string>);
begin
  ApplyRepositoryExclusions(aPatterns);
end;

procedure TUiFormTests.Exclusions_ApplyToKnownRowsAndPersist;
var
  lForm: TTestMainForm;
  lSettings: TAppSettings;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lForm.cboTargetName.Text := '';
    lForm.cboTargetName.OnChange(lForm.cboTargetName);
    lForm.AddRepoForTest('C:\RepoPulseFixture\Alpha-workspace');
    lForm.AddRepoForTest('C:\RepoPulseFixture\Beta');
    Assert.IsNotNull(lForm.btnExclusions);
    Assert.IsTrue(Assigned(lForm.btnExclusions.OnClick));
    lForm.ApplyExclusionsForTest(['*-workspace']);
    Assert.AreEqual(Cardinal(1), lForm.RepoTree.RootNodeCount);
  finally
    lForm.Free;
  end;
  lSettings := TAppSettings.Create;
  try
    lSettings.Load;
    Assert.AreEqual(1, Length(lSettings.RepositoryExclusions));
    Assert.AreEqual('*-workspace', lSettings.RepositoryExclusions[0]);
  finally
    lSettings.Free;
  end;
  lForm := TTestMainForm.Create(nil);
  try
    lForm.AddRepoForTest('C:\RepoPulseFixture\Alpha-workspace');
    lForm.AddRepoForTest('C:\RepoPulseFixture\Beta');
    lForm.ApplyExclusionsForTest([]);
    Assert.AreEqual(Cardinal(2), lForm.RepoTree.RootNodeCount,
      'Removing exclusions restores known identities without discovery');
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.PreserveSettings;
var
  lSettings: TAppSettings;
  lRules: TArray<TFolderSelectionRule>;
  i: Integer;
begin
  fSettingsExisted := TFile.Exists(TAppSettings.GetSettingsFilePath);
  if fSettingsExisted then
    fSettingsBytes := TFile.ReadAllBytes(TAppSettings.GetSettingsFilePath);
  // Existing form cases exercise status/search behavior with local fixture roots.
  // Select drives explicitly so the new folder predicate does not hide their inputs.
  SetLength(lRules, 26);
  for i := 0 to High(lRules) do
  begin
    lRules[i].Path := Char(Ord('A') + i) + ':\';
    lRules[i].Included := True;
  end;
  lSettings := TAppSettings.Create;
  try
    lSettings.FolderSelectionRules := lRules;
    lSettings.Save;
  finally
    lSettings.Free;
  end;
end;

procedure TUiFormTests.RestoreSettings;
begin
  if fSettingsExisted then
    TFile.WriteAllBytes(TAppSettings.GetSettingsFilePath, fSettingsBytes)
  else if TFile.Exists(TAppSettings.GetSettingsFilePath) then
    TFile.Delete(TAppSettings.GetSettingsFilePath);
end;

procedure TUiFormTests.SearchFilter_SurvivesRestartWithoutStartingWork;
var
  lForm: TTestMainForm;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lForm.cboTargetName.Text := 'Alpha|Beta !workspace';
    lForm.cboTargetName.OnChange(lForm.cboTargetName);
  finally
    lForm.Free;
  end;
  lForm := TTestMainForm.Create(nil);
  try
    Assert.AreEqual('Alpha|Beta !workspace', string(lForm.cboTargetName.Text));
    Assert.AreEqual(Cardinal(0), lForm.RepoTree.RootNodeCount);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.SearchFilter_ProjectsKnownRowsImmediately;
var
  lForm: TTestMainForm;
  lStatus: TRepoStatus;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := 'C:\RepoPulseFixture\Alpha';
    lStatus.IsDirty := True;
    lStatus.HasProblem := True;
    lForm.AddStatusForTest(lStatus);
    lStatus.RepoRoot := 'C:\RepoPulseFixture\Beta';
    lForm.AddStatusForTest(lStatus);
    Assert.IsTrue(Assigned(lForm.cboTargetName.OnChange));
    lForm.cboTargetName.Text := 'Alpha';
    lForm.cboTargetName.OnChange(lForm.cboTargetName);
    Assert.AreEqual(Cardinal(1), lForm.RepoTree.RootNodeCount,
      'Typing must immediately filter known rows without a scan');
    lForm.cboTargetName.Text := 'no matches';
    lForm.cboTargetName.OnChange(lForm.cboTargetName);
    Assert.AreEqual(Cardinal(0), lForm.RepoTree.RootNodeCount);
    Assert.IsFalse(lForm.btnPushVisible.Enabled, 'Bulk action must use the same projection');
    lForm.cboTargetName.Text := '';
    lForm.cboTargetName.OnChange(lForm.cboTargetName);
    Assert.AreEqual(Cardinal(2), lForm.RepoTree.RootNodeCount,
      'Clearing search restores retained rows without discovery');
  finally
    lForm.Free;
  end;
end;

function TTestMainForm.HasMutationGlyphForTest(const aStatus: TRepoStatus): Boolean;
var
  lItem: TRepoListItem;
  lPull, lPush, lMore: TRect;
begin
  lItem := Default(TRepoListItem);
  lItem.State := TRepoListItemState.rlisReady;
  lItem.Status := aStatus;
  GetRepoActionRects(lItem, Rect(0, 0, 800, 72), lPull, lPush, lMore);
  Result := not IsRectEmpty(lPull) or not IsRectEmpty(lPush);
end;

procedure TUiFormTests.InlineActions_RequireFreshStatus(const aMode: Integer);
var
  lForm: TTestMainForm;
  lStatus: TRepoStatus;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lStatus := Default(TRepoStatus);
    lStatus.IsDirty := True;
    lStatus.IsOutOfDate := True;
    lStatus.IsCached := aMode = 1;
    lStatus.ScanFailed := aMode = 2;
    Assert.AreEqual(aMode = 0, lForm.HasMutationGlyphForTest(lStatus),
      'Inline mutation buttons must use only successful current-session status');
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.Shutdown_FlushesPendingObservation;
var
  lForm: TTestMainForm;
  lCache: TRepoCache;
  lStatus: TRepoStatus;
  lRoot, lPath, lRepo, lError: string;
  lWatch: TStopwatch;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseShutdown-' + TPath.GetRandomFileName);
  ForceDirectories(lRoot);
  lPath := TPath.Combine(lRoot, 'cache.json');
  lRepo := TPath.Combine(lRoot, 'known');
  TTestMainForm.CachePathForTest := lPath;
  try
    lForm := TTestMainForm.Create(nil);
    try
      lWatch := TStopwatch.StartNew;
      repeat
        lForm.tmrUiTimer(nil);
        if lForm.btnScan.Enabled then
          Break;
        TThread.Sleep(10);
      until lWatch.ElapsedMilliseconds > 2000;
      Assert.IsTrue(lForm.btnScan.Enabled);
      lStatus := Default(TRepoStatus);
      lStatus.RepoRoot := lRepo;
      lStatus.Branch := 'pending-at-shutdown';
      lForm.SharedCacheForTest.SetInventory('known', [lRepo]);
      lForm.SharedCacheForTest.StoreStatus(lStatus, '2026-09-19T12:34:56Z');
    finally
      lForm.Free;
    end;
    lCache := TRepoCache.Create;
    try
      Assert.IsTrue(lCache.LoadFromFile(lPath, lError), lError);
      Assert.IsTrue(lCache.TryGetStatus(lRepo, lStatus), 'Shutdown must flush the pending snapshot');
      Assert.AreEqual('pending-at-shutdown', lStatus.Branch);
      Assert.AreEqual('2026-09-19T12:34:56Z', lStatus.LastAnalyzedUtc);
    finally
      lCache.Free;
    end;
  finally
    TTestMainForm.CachePathForTest := '';
    TDirectory.Delete(lRoot, True);
  end;
end;

function TTestMainForm.SharedCacheForTest: TRepoCache;
begin
  Result := RepositoryCache;
end;

procedure TTestMainForm.PerformActionForTest(const aRequest: TRepoActionRequest);
begin
  PerformRepoAction(aRequest);
end;

function TUiFormTests.RunFixtureGit(const aGit: TGitClient; const aRepo: string;
  const aArgs: TArray<string>): string;
var
  lResult: TGitResult;
  lError: string;
begin
  Assert.IsTrue(aGit.TryRunGit(aRepo, aArgs, lResult, lError), lError);
  Assert.AreEqual(0, Integer(lResult.ExitCode), lResult.OutputText);
  Result := Trim(lResult.OutputText);
end;

procedure TUiFormTests.Startup_DisablesActionsBeforeCompletion;
var
  lForm: TTestMainForm;
  lStatus: TRepoStatus;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := 'Z:\Unavailable\StreamingRow';
    lStatus.IsCached := True;
    lStatus.HasProblem := True;
    lForm.AddStatusForTest(lStatus);
    lForm.RepoActionsPopup(nil);
    Assert.IsFalse(lForm.btnScan.Enabled);
    Assert.IsFalse(lForm.miRepoFetch.Enabled, 'Fetch must wait for startup completion');
    Assert.IsFalse(lForm.miRepoRescan.Enabled, 'Analysis must wait for startup completion');
    Assert.IsFalse(lForm.FolderPane.DiscoveryEnabled,
      'Folder discovery must wait for startup completion');
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.ActionWorker_UsesSharedObservation(const aMode: Integer);
var
  lForm: TTestMainForm;
  lGit: TGitClient;
  lCache: TRepoCache;
  lStatus: TRepoStatus;
  lRequest: TRepoActionRequest;
  lRoot, lRepo, lPath, lError, lHead: string;
  lWatch: TStopwatch;
  lLock: TFileStream;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseDispatch-' + TPath.GetRandomFileName);
  lRepo := TPath.Combine(lRoot, 'repo');
  lPath := TPath.Combine(lRoot, 'cache.json');
  ForceDirectories(lRepo);
  lGit := TGitClient.Create;
  try
    RunFixtureGit(lGit, lRepo, ['init', '--initial-branch=main']);
    RunFixtureGit(lGit, lRepo, ['config', 'user.name', 'RepoPulse Test']);
    RunFixtureGit(lGit, lRepo, ['config', 'user.email', 'repopulse@example.invalid']);
    RunFixtureGit(lGit, lRepo, ['commit', '--allow-empty', '-m', 'fixture']);
    lHead := RunFixtureGit(lGit, lRepo, ['rev-parse', 'HEAD']);
    TFile.WriteAllText(TPath.Combine(lRepo, 'new.txt'), 'pending work', TEncoding.UTF8);
    lCache := TRepoCache.Create;
    try
      lCache.SetInventory('fixture', [lRepo]);
      lStatus := Default(TRepoStatus);
      lStatus.RepoRoot := lRepo;
      lStatus.Branch := 'main';
      lStatus.IsDirty := True;
      lStatus.HasProblem := True;
      lCache.StoreStatus(lStatus, '2026-09-18T12:34:56Z');
      Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    finally
      lCache.Free;
    end;
    TTestMainForm.CachePathForTest := lPath;
    lForm := TTestMainForm.Create(nil);
    try
      lWatch := TStopwatch.StartNew;
      repeat
        lForm.tmrUiTimer(nil);
        if lForm.btnScan.Enabled then
          Break;
        TThread.Sleep(10);
      until lWatch.ElapsedMilliseconds > 2000;
      Assert.IsTrue(lForm.btnScan.Enabled, 'Fixture startup must finish');
      if aMode = 1 then
      begin
        lForm.SharedCacheForTest.StoreStatus(lStatus, '2026-09-19T12:34:56Z');
        lStatus.ScanFailed := True;
        lStatus.ScanError := 'latest attempt failed after request capture';
        lForm.SharedCacheForTest.StoreStatus(lStatus, '');
      end;
      if aMode = 3 then
        lForm.SharedCacheForTest.StoreStatus(lStatus, '2026-09-19T12:34:56Z');
      lRequest := Default(TRepoActionRequest);
      lRequest.RepoRoot := lRepo;
      lRequest.MatchedFolders := [lRepo];
      lRequest.Action := TRepoAction.raCommit;
      lRequest.ActionName := 'Commit';
      lRequest.MessageText := 'must not commit stale status';
      if aMode = 2 then
      begin
        lStatus.RepoRoot := TPath.Combine(lRoot, 'pending');
        lStatus.Branch := 'pending-observation';
        lForm.SharedCacheForTest.StoreStatus(lStatus, '2026-09-19T12:34:56Z');
        lRequest.Action := TRepoAction.raRescan;
        lRequest.ActionName := 'Analyze';
      end;
      lLock := nil;
      try
        if aMode = 4 then
        begin
          lRequest.Action := TRepoAction.raRescan;
          lRequest.ActionName := 'Analyze';
          lLock := TFileStream.Create(lPath, fmOpenRead or fmShareDenyWrite);
        end;
        lForm.PerformActionForTest(lRequest);
        lForm.tmrUiTimer(nil);
        if aMode = 4 then
          Assert.IsTrue(Pos('Cache save failed', lForm.memLog.Text) > 0,
            'Successful analysis must report a failed cache write');
      finally
        lLock.Free;
      end;
      if aMode < 2 then
        Assert.AreEqual(lHead, RunFixtureGit(lGit, lRepo, ['rev-parse', 'HEAD']),
          'Final worker dispatch must reject stale mutation before Git changes HEAD')
      else if aMode = 3 then
        Assert.AreNotEqual(lHead, RunFixtureGit(lGit, lRepo, ['rev-parse', 'HEAD']),
          'A fresh observation must permit the requested commit')
      else if aMode = 2 then
      begin
        Assert.IsTrue(lForm.SharedCacheForTest.TryGetStatus(lRepo, lStatus));
        Assert.IsFalse(lStatus.IsCached, 'Action analysis must update the shared cache');
        lCache := TRepoCache.Create;
        try
          Assert.IsTrue(lCache.LoadFromFile(lPath, lError), lError);
          Assert.IsTrue(lCache.TryGetStatus(TPath.Combine(lRoot, 'pending'), lStatus),
            'Action refresh must retain unsaved observations from the shared cache');
          Assert.AreEqual('pending-observation', lStatus.Branch);
        finally
          lCache.Free;
        end;
      end;
    finally
      lForm.Free;
    end;
  finally
    TTestMainForm.CachePathForTest := '';
    lGit.Free;
    TDirectory.Delete(lRoot, True);
  end;
end;

function TTestMainForm.RepositoryCachePath: string;
begin
  if CachePathForTest <> '' then
    Result := CachePathForTest
  else
    Result := inherited RepositoryCachePath;
end;

procedure TUiFormTests.Startup_RestoresUnavailableCachedAndUnanalyzedRepositories;
var
  lForm: TTestMainForm;
  lCache: TRepoCache;
  lStatus: TRepoStatus;
  lRoot, lPath, lCachedRoot, lKnownRoot, lError, lText: string;
  lWatch: TStopwatch;
  lCreateMilliseconds: Int64;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseStartup-' + TPath.GetRandomFileName);
  lPath := TPath.Combine(lRoot, 'cache.json');
  lCachedRoot := TPath.Combine(lRoot, 'AbsentCached');
  lKnownRoot := TPath.Combine(lRoot, 'AbsentKnown');
  ForceDirectories(lRoot);
  lCache := TRepoCache.Create;
  try
    lCache.SetInventory('old-filter-must-not-limit-startup', [lCachedRoot, lKnownRoot]);
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := lCachedRoot;
    lStatus.Branch := 'saved-main';
    lStatus.IsDirty := True;
    lStatus.HasProblem := True;
    lCache.StoreStatus(lStatus, '2026-09-18T12:34:56Z');
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
  finally
    lCache.Free;
  end;
  TTestMainForm.CachePathForTest := lPath;
  try
    lWatch := TStopwatch.StartNew;
    lForm := TTestMainForm.Create(nil);
    lCreateMilliseconds := lWatch.ElapsedMilliseconds;
    try
      repeat
        lForm.tmrUiTimer(nil);
        if lForm.RepoTree.RootNodeCount = 2 then
          Break;
        TThread.Sleep(10);
      until lWatch.ElapsedMilliseconds > 2000;
      Assert.AreEqual(2, Integer(lForm.RepoTree.RootNodeCount), Format(
        'Startup must restore inventory without a scan. Create=%dms total=%dms ready=%s rules=%d included=%s log=%s',
        [lCreateMilliseconds, lWatch.ElapsedMilliseconds, BoolToStr(lForm.btnScan.Enabled, True),
        Length(lForm.FolderPane.Rules), BoolToStr(EvaluateFolderSelection(lCachedRoot, lForm.FolderPane.Rules), True),
        lForm.memLog.Text]));
      lText := lForm.RepoTree.Text[lForm.RepoTree.GetFirst, 0];
      Assert.Contains(lText, 'saved-main');
      Assert.Contains(lText, 'Last analyzed');
      Assert.Contains(lText, 'ago');
      Assert.IsFalse(lText.Contains('T12:34:56Z'));
      Assert.IsFalse(lText.Contains('[cached]'));
      lText := lForm.RepoTree.Text[lForm.RepoTree.GetNext(lForm.RepoTree.GetFirst), 0];
      Assert.Contains(lText, 'Not analyzed');
      Assert.IsFalse(lForm.btnPushVisible.Enabled);
      Assert.IsFalse(DirectoryExists(lCachedRoot));
      Assert.IsFalse(DirectoryExists(lKnownRoot));
    finally
      lForm.Free;
    end;
  finally
    TTestMainForm.CachePathForTest := '';
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TUiFormTests.Startup_ReportsAndPreservesCorruptCache;
var
  lForm: TTestMainForm;
  lRoot, lPath, lOriginal: string;
  lWatch: TStopwatch;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseBadStartup-' + TPath.GetRandomFileName);
  ForceDirectories(lRoot);
  lPath := TPath.Combine(lRoot, 'cache.json');
  lOriginal := '{broken valuable cache';
  TFile.WriteAllText(lPath, lOriginal, TEncoding.UTF8);
  TTestMainForm.CachePathForTest := lPath;
  try
    lForm := TTestMainForm.Create(nil);
    try
      lWatch := TStopwatch.StartNew;
      repeat
        lForm.tmrUiTimer(nil);
        if Pos('Cache load failed', lForm.memLog.Text) > 0 then
          Break;
        TThread.Sleep(10);
      until lWatch.ElapsedMilliseconds > 2000;
      Assert.Contains(lForm.memLog.Text, 'Cache load failed');
      Assert.AreEqual(0, Integer(lForm.RepoTree.RootNodeCount));
    finally
      lForm.Free;
    end;
    Assert.AreEqual(lOriginal, TFile.ReadAllText(lPath, TEncoding.UTF8));
  finally
    TTestMainForm.CachePathForTest := '';
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TUiFormTests.StaleStatus_DisablesMutatingUiActions(const aCached, aFailed: Boolean);
var
  g: TGarbos;
  lCache: TRepoCache;
  lForm: TTestMainForm;
  lStatus: TRepoStatus;
  lRoot, lPath, lError, lPreviousCachePath: string;
  lRoots: TArray<string>;
  lWatch: TStopwatch;
  i: Integer;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseStaleStartup-' + TPath.GetRandomFileName);
  lPath := TPath.Combine(lRoot, 'cache.json');
  lPreviousCachePath := TTestMainForm.CachePathForTest;
  ForceDirectories(lRoot);
  try
    // More than one 64-event UI batch keeps startup completion behind real inventory events.
    SetLength(lRoots, 100);
    for i := 0 to High(lRoots) do
      lRoots[i] := TPath.Combine(lRoot, 'Unanalyzed' + IntToStr(i));
    GC(lCache, TRepoCache.Create, g);
    lCache.SetInventory('stale-status-startup-fixture', lRoots);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    TTestMainForm.CachePathForTest := lPath;
    lForm := TTestMainForm.Create(nil);
    try
      lStatus := Default(TRepoStatus);
      lStatus.RepoRoot := 'Z:\Unavailable\SavedRepo';
      lStatus.Branch := 'main';
      lStatus.IsDirty := True;
      lStatus.IsOutOfDate := True;
      lStatus.HasProblem := True;
      lStatus.SubmoduleNeedsMainFastForward := True;
      lStatus.IsCached := aCached;
      lStatus.ScanFailed := aFailed;
      lForm.AddStatusForTest(lStatus);
      lWatch := TStopwatch.StartNew;
      repeat
        lForm.tmrUiTimer(nil);
        if lForm.btnScan.Enabled then
          Break;
        TThread.Sleep(10);
      until lWatch.ElapsedMilliseconds >= 2000;
      Assert.IsTrue(lForm.btnScan.Enabled, Format(
        'Valid inventory must finish loading before action checks. Elapsed=%dms rows=%d selected=%s log=%s',
        [lWatch.ElapsedMilliseconds, lForm.RepoTree.RootNodeCount,
        lForm.SelectedRootForTest, lForm.memLog.Text]));
      lForm.RepoActionsPopup(nil);
      Assert.IsFalse(lForm.btnPullVisible.Enabled, 'Cached or failed status cannot enable bulk Pull');
      Assert.IsFalse(lForm.btnPushVisible.Enabled, 'Cached or failed status cannot enable bulk Push');
      Assert.IsFalse(lForm.miRepoCommit.Enabled, 'Commit needs current-session validation');
      Assert.IsFalse(lForm.miRepoFixSubmoduleMain.Enabled, 'Corrective action needs current-session validation');
      Assert.IsTrue(lForm.miRepoRescan.Enabled, Format(
        'Analysis must remain available. Ready=%s rows=%d selected=%s rules=%d log=%s',
        [BoolToStr(lForm.btnScan.Enabled, True), lForm.RepoTree.RootNodeCount,
        lForm.SelectedRootForTest, Length(lForm.FolderPane.Rules), lForm.memLog.Text]));
      lStatus.IsCached := False;
      lStatus.ScanFailed := False;
      lForm.AddStatusForTest(lStatus);
      TThread.Sleep(110);
      lForm.tmrUiTimer(nil);
      lForm.RepoActionsPopup(nil);
      Assert.IsTrue(lForm.btnPullVisible.Enabled);
      Assert.IsTrue(lForm.btnPushVisible.Enabled);
      Assert.IsTrue(lForm.miRepoCommit.Enabled);
      Assert.IsTrue(lForm.miRepoFixSubmoduleMain.Enabled);
    finally
      lForm.Free;
    end;
  finally
    TTestMainForm.CachePathForTest := lPreviousCachePath;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TTestMainForm.HandleEventForTest(const aEvent: TUiEvent);
begin
  HandleUiEvent(aEvent);
end;

function TUiFormTests.ReadClipboardText: string;
var
  lStopwatch: TStopwatch;
begin
  lStopwatch := TStopwatch.StartNew;
  repeat
    try
      Exit(Clipboard.AsText);
    except
      on E: EClipboardException do
      begin
        if lStopwatch.ElapsedMilliseconds >= 2000 then
          raise;
      end;
    end;
    TThread.Sleep(10);
  until False;
end;

procedure TTestMainForm.AddRepoForTest(const aRepoRoot: string);
begin
  AddWaitingRepo(aRepoRoot);
  RefreshRepoTree(aRepoRoot);
end;

procedure TTestMainForm.AddStatusForTest(const aStatus: TRepoStatus);
var
  lEvent: TUiEvent;
begin
  lEvent := Default(TUiEvent);
  lEvent.Kind := TUiEventKind.uekRepoResult;
  lEvent.RepoStatus := aStatus;
  HandleUiEvent(lEvent);
  RefreshRepoTree(aStatus.RepoRoot);
end;

procedure TTestMainForm.SetSearchFilterCounts(const aMatchedCount, aDiscoveredCount: Integer;
  const aHasCounts: Boolean);
begin
  UpdateSearchFilterCaption(aMatchedCount, aDiscoveredCount, aHasCounts);
end;

procedure TTestMainForm.ShowBulkActionSummary(const aCaption, aText: string);
begin
  Inc(fBulkSummaryCount);
  fLastDialogCaption := aCaption;
  fLastDialogText := aText;
end;

procedure TTestMainForm.ShowImmediateActionError(const aCaption, aText: string);
begin
  Inc(fImmediateErrorCount);
  fLastDialogCaption := aCaption;
  fLastDialogText := aText;
end;

procedure TTestScanPathsDialog.SendKey(const aKey: Word);
var
  lKey: Word;
begin
  lKey := aKey;
  KeyDown(lKey, []);
end;

procedure TUiFormTests.AllApplicationButtons_UseBitBtn;
var
  lMainForm: TfrmMain;
  lScanForm: TfrmScanPathsDialog;
begin
  lMainForm := TfrmMain.Create(nil);
  lScanForm := TfrmScanPathsDialog.Create(nil);
  try
    Assert.AreEqual('TBitBtn', lMainForm.btnBrowseStart.ClassName);
    Assert.AreEqual('TBitBtn', lMainForm.btnScan.ClassName);
    Assert.AreEqual('TBitBtn', lMainForm.btnSettings.ClassName);
    Assert.AreEqual('TBitBtn', lMainForm.btnPullVisible.ClassName);
    Assert.AreEqual('TBitBtn', lMainForm.btnPushVisible.ClassName);
    Assert.AreEqual('TBitBtn', lMainForm.btnShowLog.ClassName);
    Assert.AreEqual('TBitBtn', lScanForm.btnAddFolder.ClassName);
    Assert.AreEqual('TBitBtn', lScanForm.btnCancel.ClassName);
    Assert.AreEqual('TBitBtn', lScanForm.btnOk.ClassName);
  finally
    lScanForm.Free;
    lMainForm.Free;
  end;
end;

procedure TUiFormTests.DiscoveryEvents_PreserveSnapshotsAndReconcileMembership(const aCancelled: Boolean);
var
  g: TGarbos;
  lCache: TRepoCache;
  lForm: TTestMainForm;
  lStatus: TRepoStatus;
  lEvent: TUiEvent;
  lRoot, lPath, lExistingRoot, lKnownRoot, lNewRoot, lError, lPreviousCachePath: string;
  lWatch: TStopwatch;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseDiscoveryUi-' + TPath.GetRandomFileName);
  lPath := TPath.Combine(lRoot, 'cache.json');
  lExistingRoot := TPath.Combine(lRoot, 'AExisting');
  lKnownRoot := TPath.Combine(lRoot, 'BKnown');
  lNewRoot := TPath.Combine(lRoot, 'CProvisional');
  lPreviousCachePath := TTestMainForm.CachePathForTest;
  ForceDirectories(lRoot);
  try
    GC(lCache, TRepoCache.Create, g);
    lCache.SetInventory('discovery-ui-fixture', [lExistingRoot, lKnownRoot]);
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := lExistingRoot;
    lStatus.Branch := 'retained-branch';
    lStatus.IsDirty := True;
    lStatus.HasProblem := True;
    lCache.StoreStatus(lStatus, '2026-09-18T12:34:56Z');
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    TTestMainForm.CachePathForTest := lPath;
    lForm := TTestMainForm.Create(nil);
    try
      lWatch := TStopwatch.StartNew;
      repeat
        lForm.tmrUiTimer(nil);
        if lForm.btnScan.Enabled then
          Break;
        TThread.Sleep(10);
      until lWatch.ElapsedMilliseconds >= 2000;
      Assert.IsTrue(lForm.btnScan.Enabled, 'Fixture inventory must finish loading');
      Assert.AreEqual(Cardinal(2), lForm.RepoTree.RootNodeCount);
      lEvent := Default(TUiEvent);
      lEvent.Kind := TUiEventKind.uekDiscoveryFound;
      lEvent.RepoRoot := lExistingRoot;
      lForm.HandleEventForTest(lEvent);
      lEvent.RepoRoot := lNewRoot;
      lForm.HandleEventForTest(lEvent);
      lForm.tmrUiTimer(nil);
      Assert.AreEqual(Cardinal(3), lForm.RepoTree.RootNodeCount,
        'Discovery adds a provisional row without clearing the existing inventory');
      Assert.Contains(lForm.RepoTree.Text[lForm.RepoTree.GetFirst, 0], 'retained-branch',
        'Rediscovery must preserve the previous snapshot');
      lEvent := Default(TUiEvent);
      lEvent.Kind := TUiEventKind.uekDiscoveryFinished;
      lEvent.OperationSucceeded := not aCancelled;
      lEvent.OperationCancelled := aCancelled;
      if aCancelled then
        lEvent.RepoRoots := [lExistingRoot, lKnownRoot]
      else
        lEvent.RepoRoots := [lExistingRoot, lNewRoot];
      lForm.HandleEventForTest(lEvent);
      lForm.tmrUiTimer(nil);
      Assert.AreEqual(Cardinal(2), lForm.RepoTree.RootNodeCount,
        'The terminal event restores the exact committed inventory');
      Assert.Contains(lForm.RepoTree.Text[lForm.RepoTree.GetFirst, 0], 'retained-branch');
      lForm.cboTargetName.Text := 'CProvisional';
      lForm.cboTargetNameChange(nil);
      Assert.AreEqual(Cardinal(Ord(not aCancelled)), lForm.RepoTree.RootNodeCount,
        'Only completed discovery retains provisional membership');
      lForm.cboTargetName.Text := 'BKnown';
      lForm.cboTargetNameChange(nil);
      Assert.AreEqual(Cardinal(Ord(aCancelled)), lForm.RepoTree.RootNodeCount,
        'Cancellation preserves the prior committed membership');
    finally
      lForm.Free;
    end;
  finally
    TTestMainForm.CachePathForTest := lPreviousCachePath;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TUiFormTests.DiscoveryEvents_PreserveSelectedRootAcrossInsertionsAndTerminal(const aCancelled: Boolean);
var
  g: TGarbos;
  lCache: TRepoCache;
  lForm: TTestMainForm;
  lEvent: TUiEvent;
  lNode: PVirtualNode;
  lRoot, lPath, lFirst, lSelected, lInserted, lPending, lError, lPreviousCachePath: string;
  lWatch: TStopwatch;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseFocusUi-' + TPath.GetRandomFileName);
  lPath := TPath.Combine(lRoot, 'cache.json');
  lFirst := TPath.Combine(lRoot, 'A');
  lSelected := TPath.Combine(lRoot, 'B');
  lInserted := TPath.Combine(lRoot, 'AA');
  lPending := TPath.Combine(lRoot, 'AB');
  lPreviousCachePath := TTestMainForm.CachePathForTest;
  ForceDirectories(lRoot);
  try
    GC(lCache, TRepoCache.Create, g);
    lCache.SetInventory('focus-ui-fixture', [lFirst, lSelected]);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    TTestMainForm.CachePathForTest := lPath;
    lForm := TTestMainForm.Create(nil);
    try
      lWatch := TStopwatch.StartNew;
      repeat
        lForm.tmrUiTimer(nil);
        if lForm.btnScan.Enabled then
          Break;
        TThread.Sleep(10);
      until lWatch.ElapsedMilliseconds >= 2000;
      Assert.IsTrue(lForm.btnScan.Enabled, 'Fixture startup must complete');
      Assert.AreEqual(Cardinal(2), lForm.RepoTree.RootNodeCount);
      lNode := lForm.RepoTree.GetNext(lForm.RepoTree.GetFirst);
      lForm.RepoTree.FocusedNode := lNode;
      lForm.RepoTree.Selected[lNode] := True;
      Assert.AreEqual(lSelected, lForm.SelectedRootForTest, 'The fixture must initially select B');
      lEvent := Default(TUiEvent);
      lEvent.Kind := TUiEventKind.uekDiscoveryFound;
      lEvent.RepoRoot := lInserted;
      lForm.HandleEventForTest(lEvent);
      lForm.tmrUiTimer(nil);
      Assert.AreEqual(lSelected, lForm.SelectedRootForTest,
        'Inserting a sorted discovery before B must preserve B as the selected repository');
      lEvent.RepoRoot := lPending;
      lForm.HandleEventForTest(lEvent);
      lEvent := Default(TUiEvent);
      lEvent.Kind := TUiEventKind.uekDiscoveryFinished;
      lEvent.OperationSucceeded := not aCancelled;
      lEvent.OperationCancelled := aCancelled;
      if aCancelled then
        lEvent.RepoRoots := [lFirst, lSelected]
      else
        lEvent.RepoRoots := [lFirst, lInserted, lPending, lSelected];
      lForm.HandleEventForTest(lEvent);
      lForm.tmrUiTimer(nil);
      Assert.AreEqual(lSelected, lForm.SelectedRootForTest,
        'Terminal reconciliation must preserve B when another insertion is still pending');
    finally
      lForm.Free;
    end;
  finally
    TTestMainForm.CachePathForTest := lPreviousCachePath;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TUiFormTests.Filters_PreserveSelectedRootWhileDiscoveryRefreshIsPending(const aFilter: Integer);
var
  g: TGarbos;
  lCache: TRepoCache;
  lSettings: TAppSettings;
  lForm: TTestMainForm;
  lEvent: TUiEvent;
  lNode: PVirtualNode;
  lFolderNode: TTreeNode;
  lRules: TArray<TFolderSelectionRule>;
  lRoot, lPath, lFirst, lSelected, lInserted, lOther, lError, lPreviousCachePath: string;
  lWatch: TStopwatch;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulsePendingFocusUi-' + TPath.GetRandomFileName);
  lPath := TPath.Combine(lRoot, 'cache.json');
  lFirst := TPath.Combine(lRoot, 'A');
  lSelected := TPath.Combine(lRoot, 'B');
  lInserted := TPath.Combine(lRoot, 'AA');
  lOther := lRoot + '-Other';
  lPreviousCachePath := TTestMainForm.CachePathForTest;
  ForceDirectories(lRoot);
  try
    GC(lCache, TRepoCache.Create, g);
    lCache.SetInventory('pending-focus-ui-fixture', [lFirst, lSelected]);
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    GC(lSettings, TAppSettings.Create, g);
    lSettings.Load;
    lSettings.TargetRepoName := 'RepoPulsePendingFocusUi';
    lSettings.StatusFilterIndex := Ord(TRepoFilter.rfAttention);
    lSettings.RepositoryExclusions := [];
    SetLength(lRules, 2);
    lRules[0].Path := lRoot;
    lRules[0].Included := True;
    lRules[1].Path := lOther;
    lRules[1].Included := True;
    lSettings.FolderSelectionRules := lRules;
    lSettings.Save;
    TTestMainForm.CachePathForTest := lPath;
    lForm := TTestMainForm.Create(nil);
    try
      lWatch := TStopwatch.StartNew;
      repeat
        lForm.tmrUiTimer(nil);
        if lForm.btnScan.Enabled then
          Break;
        TThread.Sleep(10);
      until lWatch.ElapsedMilliseconds >= 2000;
      Assert.IsTrue(lForm.btnScan.Enabled, 'Fixture startup must complete');
      Assert.AreEqual(Cardinal(2), lForm.RepoTree.RootNodeCount);
      lNode := lForm.RepoTree.GetNext(lForm.RepoTree.GetFirst);
      lForm.RepoTree.FocusedNode := lNode;
      lForm.RepoTree.Selected[lNode] := True;
      Assert.AreEqual(lSelected, lForm.SelectedRootForTest, 'The fixture must initially select B');
      lEvent := Default(TUiEvent);
      lEvent.Kind := TUiEventKind.uekDiscoveryFound;
      lEvent.RepoRoot := lInserted;
      lForm.HandleEventForTest(lEvent);
      Assert.AreEqual(Cardinal(2), lForm.RepoTree.RootNodeCount,
        'The insertion must remain pending until the user changes a filter');
      case aFilter of
        0:
          begin
            lForm.cboTargetName.Text := ExtractFileName(lRoot);
            lForm.cboTargetNameChange(nil);
          end;
        1:
          begin
            lFolderNode := TFolderTreeAccess(lForm.FolderPane).FindNode(lOther);
            Assert.IsNotNull(lFolderNode);
            lFolderNode.CheckState := TNodeCheckState.ncsUnchecked;
          end;
        2:
          begin
            lForm.cboStatusFilter.ItemIndex := Ord(TRepoFilter.rfAll);
            lForm.cboStatusFilterChange(nil);
          end;
        3: lForm.ApplyExclusionsForTest(['*NeverMatchesThisFixture*']);
        4: lForm.btnClearFilters.Click;
      end;
      Assert.AreEqual(Cardinal(3), lForm.RepoTree.RootNodeCount,
        'Each filter change must retain all three fixture repositories');
      Assert.AreEqual(lSelected, lForm.SelectedRootForTest,
        'Changing a filter before the discovery timer must immediately preserve selected B');
      lForm.tmrUiTimer(nil);
      Assert.AreEqual(lSelected, lForm.SelectedRootForTest,
        'The subsequent timer must keep the same selected repository');
    finally
      lForm.Free;
    end;
  finally
    TTestMainForm.CachePathForTest := lPreviousCachePath;
    TDirectory.Delete(lRoot, True);
  end;
end;
procedure TUiFormTests.Analysis_CapturesVisibleCachedAndWaitingRootsBeforeFilterChanges;
var
  g: TGarbos;
  lGit: TGitClient;
  lCache: TRepoCache;
  lSettings: TAppSettings;
  lForm: TTestMainForm;
  lAnalyze: TComponent;
  lStatus: TRepoStatus;
  lRoots, lObservations: TArray<string>;
  lNode: PVirtualNode;
  lRoot, lPath, lError, lPreviousCachePath: string;
  lWatch: TStopwatch;
  i: Integer;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseAnalysisUi-' + TPath.GetRandomFileName);
  lPath := TPath.Combine(lRoot, 'cache.json');
  lRoots := [TPath.Combine(lRoot, 'AlphaCached'), TPath.Combine(lRoot, 'AlphaWaiting'),
    TPath.Combine(lRoot, 'BetaHidden'), TPath.Combine(lRoot, 'AlphaExcluded')];
  lPreviousCachePath := TTestMainForm.CachePathForTest;
  ForceDirectories(lRoot);
  try
    GC(lGit, TGitClient.Create, g);
    for i := 0 to High(lRoots) do
    begin
      ForceDirectories(lRoots[i]);
      RunFixtureGit(lGit, lRoots[i], ['init', '--initial-branch=main']);
      RunFixtureGit(lGit, lRoots[i], ['config', 'user.name', 'RepoPulse Test']);
      RunFixtureGit(lGit, lRoots[i], ['config', 'user.email', 'repopulse@example.invalid']);
      RunFixtureGit(lGit, lRoots[i], ['commit', '--allow-empty', '-m', 'fixture']);
    end;
    GC(lCache, TRepoCache.Create, g);
    lCache.SetInventory('analysis-ui-fixture', lRoots);
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := lRoots[0];
    lStatus.Branch := 'old-observation';
    lCache.StoreStatus(lStatus, '2026-09-18T12:34:56Z');
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    GC(lSettings, TAppSettings.Create, g);
    lSettings.Load;
    lSettings.TargetRepoName := 'Alpha';
    lSettings.StatusFilterIndex := Ord(TRepoFilter.rfAll);
    lSettings.RepositoryExclusions := ['*Excluded'];
    lSettings.ThrottleLimit := 1;
    lSettings.Save;
    TTestMainForm.CachePathForTest := lPath;
    lForm := TTestMainForm.Create(nil);
    try
      lWatch := TStopwatch.StartNew;
      repeat
        lForm.tmrUiTimer(nil);
        if lForm.btnScan.Enabled then
          Break;
        TThread.Sleep(10);
      until lWatch.ElapsedMilliseconds >= 2000;
      Assert.IsTrue(lForm.btnScan.Enabled, 'Fixture inventory must finish loading');
      Assert.AreEqual(Cardinal(2), lForm.RepoTree.RootNodeCount);
      lAnalyze := lForm.FindComponent('btnAnalyzeRepos');
      Assert.IsNotNull(lAnalyze, 'Visible repository analysis needs its own command');
      Assert.IsTrue(TBitBtn(lAnalyze).Enabled, 'Cached and never-analyzed roots are eligible');
      TBitBtn(lAnalyze).Click;
      Assert.IsTrue(lForm.cboTargetName.Enabled, 'Search stays usable during analysis');
      Assert.IsTrue(lForm.FolderPane.Enabled, 'Folder selection stays usable during analysis');
      Assert.IsFalse(lForm.FolderPane.DiscoveryEnabled,
        'Folder discovery must be disabled while analysis owns the job');
      lForm.cboTargetName.Text := 'Beta';
      lForm.cboTargetNameChange(nil);
      Assert.AreEqual(Cardinal(1), lForm.RepoTree.RootNodeCount);
      lWatch := TStopwatch.StartNew;
      repeat
        lForm.tmrUiTimer(nil);
        if lForm.btnScan.Enabled and (lForm.btnScan.Caption = 'Update Repo list') then
          Break;
        TThread.Sleep(10);
      until lWatch.ElapsedMilliseconds >= 10000;
      Assert.AreEqual('Update Repo list', lForm.btnScan.Caption,
        'Analysis must finish its captured scope: ' + lForm.memLog.Text);
      Assert.IsTrue(lForm.SharedCacheForTest.TryGetStatus(lRoots[0], lStatus));
      Assert.IsFalse(lStatus.ScanFailed, lStatus.ScanError);
      Assert.AreNotEqual('2026-09-18T12:34:56Z', lStatus.LastAnalyzedUtc,
        'The originally visible cached root must be refreshed');
      Assert.IsTrue(lForm.SharedCacheForTest.TryGetStatus(lRoots[1], lStatus),
        'The originally visible never-analyzed root must be analyzed');
      Assert.IsFalse(lStatus.ScanFailed, lStatus.ScanError);
      Assert.IsFalse(lForm.SharedCacheForTest.TryGetStatus(lRoots[2], lStatus),
        'A root revealed after invocation must not enter the captured analysis');
      Assert.IsFalse(lForm.SharedCacheForTest.TryGetStatus(lRoots[3], lStatus),
        'An excluded root must remain outside analysis');
      lForm.cboTargetName.Text := 'NoSuchRepository';
      lForm.cboTargetNameChange(nil);
      Assert.IsFalse(TBitBtn(lAnalyze).Enabled, 'Zero visible roots disable analysis');
      TBitBtn(lAnalyze).Click;
      Assert.AreEqual('Update Repo list', lForm.btnScan.Caption,
        'Invoking an empty analysis must not start a job');
      SetLength(lObservations, 2);
      for i := 0 to 1 do
      begin
        Assert.IsTrue(lForm.SharedCacheForTest.TryGetStatus(lRoots[i], lStatus));
        Assert.IsFalse(lStatus.IsDirty, 'The original analysis fixture must start clean');
        lObservations[i] := lStatus.LastAnalyzedUtc;
        TFile.WriteAllText(TPath.Combine(lRoots[i], 'changed-after-batch'), 'new worktree content');
        Assert.IsTrue(RunFixtureGit(lGit, lRoots[i], ['status', '--porcelain']) <> '',
          'Fixture worktree edits must be observable by Git');
      end;
      lForm.cboTargetName.Text := '';
      lForm.cboTargetNameChange(nil);
      Assert.AreEqual(Cardinal(3), lForm.RepoTree.RootNodeCount);
      lNode := lForm.RepoTree.GetNext(lForm.RepoTree.GetNext(lForm.RepoTree.GetFirst));
      lForm.RepoTree.FocusedNode := lNode;
      lForm.RepoTree.Selected[lNode] := True;
      Assert.AreEqual(lRoots[2], lForm.SelectedRootForTest);
      lForm.RepoActionsPopup(nil);
      Assert.IsTrue(lForm.miRepoRescan.Enabled);
      lForm.miRepoRescan.Click;
      lWatch := TStopwatch.StartNew;
      repeat
        lForm.tmrUiTimer(nil);
        if lForm.btnScan.Enabled and (lForm.btnScan.Caption = 'Update Repo list') then
          Break;
        TThread.Sleep(10);
      until lWatch.ElapsedMilliseconds >= 10000;
      Assert.AreEqual('Update Repo list', lForm.btnScan.Caption,
        'Single-repository analysis must finish: ' + lForm.memLog.Text);
      Assert.IsTrue(lForm.SharedCacheForTest.TryGetStatus(lRoots[2], lStatus),
        'The popup analysis command must analyze the selected repository');
      Assert.IsFalse(lStatus.ScanFailed, lStatus.ScanError);
      for i := 0 to 1 do
      begin
        Assert.IsTrue(lForm.SharedCacheForTest.TryGetStatus(lRoots[i], lStatus));
        Assert.IsFalse(lStatus.IsDirty,
          'Single-repository analysis must not refresh other visible repositories');
        Assert.AreEqual(lObservations[i], lStatus.LastAnalyzedUtc);
      end;
      Assert.IsFalse(lForm.SharedCacheForTest.TryGetStatus(lRoots[3], lStatus),
        'The hidden excluded repository must remain unanalyzed');
    finally
      lForm.Free;
    end;
  finally
    TTestMainForm.CachePathForTest := lPreviousCachePath;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TUiFormTests.FolderContext_DiscoveryKeepsUncheckedResultsHiddenAndPreservesRules;
var
  g: TGarbos;
  lCache: TRepoCache;
  lSettings: TAppSettings;
  lForm: TTestMainForm;
  lStatus: TRepoStatus;
  lRules, lBeforeRules: TArray<TFolderSelectionRule>;
  lInventory: TArray<string>;
  lRoot, lPath, lChecked, lUnchecked, lExisting, lFound, lError, lPreviousCachePath: string;
  lHasExisting, lHasFound: Boolean;
  lWatch: TStopwatch;
  i: Integer;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseContextUi-' + TPath.GetRandomFileName);
  lPath := TPath.Combine(lRoot, 'cache.json');
  lChecked := TPath.Combine(lRoot, 'Checked');
  lUnchecked := TPath.Combine(lRoot, 'Unchecked');
  lExisting := TPath.Combine(lChecked, 'Existing');
  lFound := TPath.Combine(lUnchecked, 'Found');
  lPreviousCachePath := TTestMainForm.CachePathForTest;
  ForceDirectories(lRoot);
  try
    ForceDirectories(TPath.Combine(lExisting, '.git'));
    ForceDirectories(TPath.Combine(lFound, '.git'));
    GC(lCache, TRepoCache.Create, g);
    lCache.SetInventory('context-ui-fixture', [lExisting]);
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := lExisting;
    lStatus.Branch := 'preserved-observation';
    lStatus.HasProblem := True;
    lCache.StoreStatus(lStatus, '2026-09-18T12:34:56Z');
    Assert.IsTrue(lCache.SaveToFile(lPath, 3600, lError), lError);
    GC(lSettings, TAppSettings.Create, g);
    lSettings.Load;
    SetLength(lRules, 1);
    lRules[0].Path := lChecked;
    lRules[0].Included := True;
    lSettings.FolderSelectionRules := lRules;
    lSettings.TargetRepoName := '*';
    lSettings.StatusFilterIndex := Ord(TRepoFilter.rfAll);
    lSettings.Save;
    TTestMainForm.CachePathForTest := lPath;
    lForm := TTestMainForm.Create(nil);
    try
      lWatch := TStopwatch.StartNew;
      repeat
        lForm.tmrUiTimer(nil);
        if lForm.btnScan.Enabled then
          Break;
        TThread.Sleep(10);
      until lWatch.ElapsedMilliseconds >= 2000;
      Assert.IsTrue(lForm.btnScan.Enabled, 'Fixture startup must complete');
      Assert.AreEqual(Cardinal(1), lForm.RepoTree.RootNodeCount);
      lBeforeRules := lForm.FolderPane.Rules;
      Assert.IsTrue(Assigned(lForm.FolderPane.OnDiscoverHere),
        'The folder context command must invoke one-off discovery in the main form');
      lForm.FolderPane.OnDiscoverHere(lForm.FolderPane, lUnchecked);
      lWatch := TStopwatch.StartNew;
      repeat
        lForm.tmrUiTimer(nil);
        if lForm.btnScan.Enabled and (lForm.btnScan.Caption = 'Update Repo list') then
          Break;
        TThread.Sleep(10);
      until lWatch.ElapsedMilliseconds >= 5000;
      Assert.AreEqual('Update Repo list', lForm.btnScan.Caption,
        'One-off discovery must finish: ' + lForm.memLog.Text);
      lRules := lForm.FolderPane.Rules;
      Assert.AreEqual(Length(lBeforeRules), Length(lRules));
      for i := 0 to High(lRules) do
      begin
        Assert.AreEqual(lBeforeRules[i].Path, lRules[i].Path);
        Assert.AreEqual(lBeforeRules[i].Included, lRules[i].Included);
      end;
      Assert.AreEqual('*', lForm.cboTargetName.Text);
      Assert.AreEqual(Cardinal(1), lForm.RepoTree.RootNodeCount,
        'The discovered unchecked repository must remain hidden');
      lInventory := lForm.SharedCacheForTest.GetInventory;
      Assert.AreEqual(2, Length(lInventory), 'Discovery must retain the unrelated cached repository');
      lHasExisting := False;
      lHasFound := False;
      for i := 0 to High(lInventory) do
      begin
        lHasExisting := lHasExisting or SameText(lInventory[i], lExisting);
        lHasFound := lHasFound or SameText(lInventory[i], lFound);
      end;
      Assert.IsTrue(lHasExisting);
      Assert.IsTrue(lHasFound, 'Unchecked context discovery must retain the new repository in cache');
      Assert.IsFalse(lForm.SharedCacheForTest.TryGetStatus(lFound, lStatus),
        'One-off discovery must not analyze the discovered repository');
      Assert.IsTrue(lForm.SharedCacheForTest.TryGetStatus(lExisting, lStatus));
      Assert.AreEqual('preserved-observation', lStatus.Branch);
      Assert.AreEqual('2026-09-18T12:34:56Z', lStatus.LastAnalyzedUtc);
      Assert.Contains(lForm.stsMain.SimpleText, '1 found');
      Assert.Contains(lForm.stsMain.SimpleText, '1 visible overall',
        'The summary must distinguish total visible inventory from the unchecked discoveries');
    finally
      lForm.Free;
    end;
  finally
    TTestMainForm.CachePathForTest := lPreviousCachePath;
    TDirectory.Delete(lRoot, True);
  end;
end;

procedure TUiFormTests.RepositoryAccessibilityText_OmitsAbsolutePath(const aCached: Boolean);
var
  g: TGarbos;
  lForm: TTestMainForm;
  lStatus: TRepoStatus;
  lRoot, lText: string;
begin
  GC(lForm, TTestMainForm.Create(nil), g);
  lRoot := 'C:\RepoPulseFixture\Alpha';
  if aCached then
  begin
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := lRoot;
    lStatus.Branch := 'cached-main';
    lStatus.IsCached := True;
    lStatus.HasProblem := True;
    lStatus.LastAnalyzedUtc := '2026-09-18T12:34:56Z';
    lForm.AddStatusForTest(lStatus);
  end else
    lForm.AddRepoForTest(lRoot);
  Assert.AreEqual(Cardinal(1), lForm.RepoTree.RootNodeCount);
  lText := lForm.RepoTree.Text[lForm.RepoTree.GetFirst, 0];
  Assert.IsFalse(lText.ToLowerInvariant.Contains(lRoot.ToLowerInvariant),
    'Automatic row speech should not delay status behind the absolute repository path');
  Assert.Contains(lText, 'Alpha');
  if aCached then
  begin
    Assert.Contains(lText, 'ago');
    Assert.IsFalse(lText.Contains('T12:34:56Z'));
    Assert.IsFalse(lText.Contains('[cached]'));
  end else
    Assert.Contains(lText, 'Not analyzed');
end;

procedure TUiFormTests.RepositoryAccessibilityText_UsesRelativeAge(const aMode: Integer);
var
  g: TGarbos;
  lForm: TTestMainForm;
  lStatus: TRepoStatus;
  lObservedLocal: TDateTime;
  lText, lExpected: string;
  lPreviousFormatSettings: TFormatSettings;
begin
  GC(lForm, TTestMainForm.Create(nil), g);
  lStatus := Default(TRepoStatus);
  lStatus.RepoRoot := 'C:\RepoPulseFixture\Alpha';
  lStatus.Branch := 'main';
  lStatus.HasProblem := True;
  lStatus.IsCached := True;
  case aMode of
    0:
      begin
        lObservedLocal := Now - EncodeTime(0, 10, 30, 0);
        lExpected := '10 minutes ago';
      end;
    1:
      begin
        lObservedLocal := Now - EncodeTime(2, 0, 30, 0);
        lExpected := '2 hours ago';
      end;
    2:
      begin
        lObservedLocal := Now - 3 - EncodeTime(0, 0, 30, 0);
        lExpected := '3 days ago';
      end;
    3:
      begin
        lObservedLocal := Now - 65 - EncodeTime(0, 0, 30, 0);
        lExpected := '2 months ago';
      end;
    4:
      begin
        lObservedLocal := Now - 800 - EncodeTime(0, 0, 30, 0);
        lExpected := '2 years ago';
      end;
    5:
      begin
        lObservedLocal := Now - EncodeTime(0, 1, 30, 0);
        lExpected := '1 minute ago';
      end;
    6:
      begin
        lObservedLocal := Now - EncodeTime(1, 0, 30, 0);
        lExpected := '1 hour ago';
      end;
    7:
      begin
        lObservedLocal := Now - 1 - EncodeTime(0, 0, 30, 0);
        lExpected := '1 day ago';
      end;
    8:
      begin
        lObservedLocal := Now - 32 - EncodeTime(0, 0, 30, 0);
        lExpected := '1 month ago';
      end;
    9:
      begin
        lObservedLocal := Now - 400 - EncodeTime(0, 0, 30, 0);
        lExpected := '1 year ago';
      end;
  else
    begin
      lObservedLocal := Now - EncodeTime(0, 0, 30, 0);
      lExpected := 'just now';
    end;
  end;
  lStatus.LastAnalyzedUtc := DateToISO8601(TTimeZone.Local.ToUniversalTime(lObservedLocal), True);
  lForm.AddRepoForTest(lStatus.RepoRoot);
  lPreviousFormatSettings := FormatSettings;
  try
    if aMode = 4 then
      FormatSettings := TFormatSettings.Create('pl-PL');
    lForm.AddStatusForTest(lStatus);
    lText := lForm.RepoTree.Text[lForm.RepoTree.GetFirst, 0];
  finally
    FormatSettings := lPreviousFormatSettings;
  end;
  Assert.Contains(lText, 'Last analyzed');
  Assert.Contains(lText, lExpected);
  Assert.IsFalse(lText.Contains('[cached]'));
  Assert.IsFalse(lText.Contains('T00:00:00'));
end;

procedure TUiFormTests.RepositoryCommands_SeparateDiscoveryFromAnalysis;
var
  g: TGarbos;
  lForm: TTestMainForm;
  lAnalyze: TComponent;
begin
  GC(lForm, TTestMainForm.Create(nil), g);
  lAnalyze := lForm.FindComponent('btnAnalyzeRepos');
  Assert.IsNotNull(lAnalyze, 'Repository analysis needs a separate command from inventory discovery');
  Assert.IsTrue(lAnalyze is TBitBtn, 'The analysis command must use the application button type');
  Assert.AreEqual('Analyze Repos', TBitBtn(lAnalyze).Caption);
  Assert.AreEqual('Update Repo list', lForm.btnScan.Caption);
  Assert.AreEqual('Analyze this repo', lForm.miRepoRescan.Caption);
  Assert.IsTrue(Assigned(TBitBtn(lAnalyze).OnClick), 'The separate analysis command must be actionable');
end;

procedure TUiFormTests.Toolbar_ScanIsLeftmostAction;
var
  lForm: TfrmMain;
begin
  lForm := TfrmMain.Create(nil);
  try
    Assert.IsTrue(lForm.btnScan.Left < lForm.btnPullVisible.Left);
    Assert.IsTrue(lForm.btnPullVisible.Left < lForm.btnPushVisible.Left);
    Assert.IsTrue(lForm.btnPushVisible.Left < lForm.btnSettings.Left);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.Toolbar_AllActionsHaveDistinctSvgImages;
var
  lForm: TfrmMain;
begin
  lForm := TfrmMain.Create(nil);
  try
    Assert.IsNotNull(lForm.btnScan.Images);
    Assert.AreSame(lForm.btnScan.Images, lForm.btnPullVisible.Images);
    Assert.AreSame(lForm.btnScan.Images, lForm.btnPushVisible.Images);
    Assert.AreSame(lForm.btnScan.Images, lForm.btnSettings.Images);
    Assert.AreNotEqual(lForm.btnScan.ImageIndex, lForm.btnPullVisible.ImageIndex);
    Assert.AreNotEqual(lForm.btnScan.ImageIndex, lForm.btnPushVisible.ImageIndex);
    Assert.AreNotEqual(lForm.btnScan.ImageIndex, lForm.btnSettings.ImageIndex);
    Assert.AreNotEqual(lForm.btnPullVisible.ImageIndex, lForm.btnPushVisible.ImageIndex);
    Assert.AreNotEqual(lForm.btnPullVisible.ImageIndex, lForm.btnSettings.ImageIndex);
    Assert.AreNotEqual(lForm.btnPushVisible.ImageIndex, lForm.btnSettings.ImageIndex);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.ScanActivity_UsesSkillSearchAnimatedControl;
var
  lForm: TfrmMain;
  lAnimation: TComponent;
begin
  lForm := TfrmMain.Create(nil);
  try
    lAnimation := lForm.FindComponent('ScanAnimation');
    Assert.IsNotNull(lAnimation);
    Assert.AreEqual('TSkAnimatedImage', lAnimation.ClassName);
    Assert.IsNotNull(lForm.FindComponent('ActivityPanel'));
    Assert.AreEqual(168, lForm.ActivityPanel.Height);
    Assert.AreEqual(128, lForm.ScanAnimation.Width);
    Assert.AreEqual(136, lForm.ScanAnimation.Height);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.BulkActivity_ShowsProgressStatusAndAnimation;
var
  lAnimation: TControl;
  lEvent: TUiEvent;
  lForm: TTestMainForm;
  lWatch: TStopwatch;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lWatch := TStopwatch.StartNew;
    repeat
      lForm.tmrUiTimer(nil);
      if lForm.btnScan.Enabled then
        Break;
      TThread.Sleep(10);
    until lWatch.ElapsedMilliseconds >= 2000;
    Assert.IsTrue(lForm.btnScan.Enabled,
      'Startup must complete before a bulk job can begin: ' + lForm.memLog.Text);
    lAnimation := TControl(lForm.FindComponent('BulkAnimation'));
    Assert.IsNotNull(lAnimation);
    Assert.AreEqual('TSkAnimatedImage', lAnimation.ClassName);
    Assert.AreEqual(128, lAnimation.Width);
    Assert.AreEqual(136, lAnimation.Height);

    lEvent := Default(TUiEvent);
    lEvent.Kind := TUiEventKind.uekProgressStart;
    lEvent.ProgressMode := TProgressMode.pmDeterminate;
    lEvent.ProgressMax := 4;
    lEvent.Text := 'Pulling 0 of 4 repositories...';
    lForm.HandleEventForTest(lEvent);
    Assert.IsTrue(lForm.pbProgress.Visible);
    Assert.AreEqual(4, lForm.pbProgress.Max);
    Assert.AreEqual(0, lForm.pbProgress.Position);
    Assert.AreEqual(lEvent.Text, lForm.stsMain.SimpleText);
    Assert.IsTrue(lAnimation.Visible);
    Assert.IsFalse(lForm.btnScan.Enabled);
    Assert.IsFalse(lForm.btnSettings.Enabled);
    Assert.IsFalse(lForm.cboStatusFilter.Enabled);
    Assert.IsFalse(lForm.FolderPane.DiscoveryEnabled,
      'Folder discovery must be disabled while a mutation job is active');

    lEvent.Kind := TUiEventKind.uekProgressUpdate;
    lEvent.ProgressValue := 3;
    lEvent.Text := 'Pulling 3 of 4 repositories...';
    lForm.HandleEventForTest(lEvent);
    Assert.AreEqual(3, lForm.pbProgress.Position);
    Assert.AreEqual(lEvent.Text, lForm.stsMain.SimpleText);

    lEvent.Kind := TUiEventKind.uekProgressEnd;
    lEvent.Text := 'Pull finished for 4 repositories.';
    lForm.HandleEventForTest(lEvent);
    Assert.IsFalse(lForm.pbProgress.Visible);
    Assert.IsFalse(lAnimation.Visible);
    Assert.AreEqual(lEvent.Text, lForm.stsMain.SimpleText);
    Assert.IsTrue(lForm.btnScan.Enabled,
      'Bulk completion must restore discovery once startup and queued work are complete: ' + lForm.memLog.Text);
    Assert.IsTrue(lForm.btnSettings.Enabled);
    Assert.IsTrue(lForm.cboStatusFilter.Enabled);
    Assert.IsTrue(lForm.FolderPane.DiscoveryEnabled,
      'Folder discovery must be restored after mutation completion');
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.Settings_SeparatesScanAndActionThreadLimits;
var
  lActionEdit: TComponent;
  lActionLabel: TComponent;
  lForm: TfrmMain;
begin
  lForm := TfrmMain.Create(nil);
  try
    lActionEdit := lForm.FindComponent('edtActionThrottle');
    lActionLabel := lForm.FindComponent('lblActionThrottle');
    Assert.IsNotNull(lActionEdit);
    Assert.IsNotNull(lActionLabel);
    Assert.AreSame(lForm.edtThrottle, lForm.lblThrottle.FocusControl);
    Assert.AreSame(lActionEdit, TStaticText(lActionLabel).FocusControl);
    Assert.AreNotEqual(lForm.lblThrottle.Caption, TStaticText(lActionLabel).Caption);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.ScanPathsDialog_EscapeCancels;
var
  lForm: TTestScanPathsDialog;
begin
  lForm := TTestScanPathsDialog.Create(nil);
  try
    lForm.ModalResult := mrNone;
    lForm.SendKey(VK_ESCAPE);
    Assert.AreEqual(mrCancel, lForm.ModalResult);
  finally
    lForm.Free;
  end;
end;

procedure TTestScanPathsDialog.SetIgnorePath(const aPath: string);
begin
  fIgnorePath := aPath;
end;

procedure TUiFormTests.ScanPathsDialog_CombinesScanAndIgnoredPaths;
var
  lMainForm: TfrmMain;
  lScanForm: TfrmScanPathsDialog;
  lIgnoreMemo: TComponent;
  lIgnoreLabel: TComponent;
begin
  lMainForm := TfrmMain.Create(nil);
  lScanForm := TfrmScanPathsDialog.Create(nil);
  try
    lIgnoreMemo := lScanForm.FindComponent('memIgnorePaths');
    lIgnoreLabel := lScanForm.FindComponent('lblIgnorePaths');
    Assert.IsNotNull(lIgnoreMemo);
    Assert.IsNotNull(lIgnoreLabel);
    Assert.AreSame(lIgnoreMemo, TStaticText(lIgnoreLabel).FocusControl);
    Assert.IsNull(lMainForm.FindComponent('pnlIgnoreDirs'));
    Assert.IsNull(lMainForm.FindComponent('btnEditIgnoreDirs'));
  finally
    lScanForm.Free;
    lMainForm.Free;
  end;
end;

procedure TUiFormTests.ScanPathsDialog_SavePersistsIgnoreRules;
var
  lForm: TTestScanPathsDialog;
  lTempRoot: string;
  lIgnorePath: string;
  lSaved: TStringList;
begin
  lTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseDialogSave-' + TPath.GetRandomFileName);
  lIgnorePath := TPath.Combine(TPath.Combine(lTempRoot, 'settings'), '.ignoredirectory');
  ForceDirectories(lTempRoot);
  try
    lForm := TTestScanPathsDialog.Create(nil);
    try
      lForm.SetIgnorePath(lIgnorePath);
      lForm.memPaths.Lines.Text := lTempRoot;
      lForm.memIgnorePaths.Lines.Text := '.git' + sLineBreak + 'build/*';
      lForm.btnOkClick(nil);

      Assert.AreEqual(mrOk, lForm.ModalResult);
      Assert.IsTrue(FileExists(lIgnorePath));
      lSaved := TStringList.Create;
      try
        lSaved.LoadFromFile(lIgnorePath, TEncoding.UTF8);
        Assert.AreEqual(2, lSaved.Count);
        Assert.AreEqual('.git', lSaved[0]);
        Assert.AreEqual('build/*', lSaved[1]);
      finally
        lSaved.Free;
      end;
    finally
      lForm.Free;
    end;
  finally
    if DirectoryExists(lTempRoot) then
      TDirectory.Delete(lTempRoot, True);
  end;
end;

procedure TUiFormTests.RepositoryView_UsesVirtualStringTree;
var
  lForm: TfrmMain;
  lTree: TComponent;
begin
  lForm := TfrmMain.Create(nil);
  try
    lTree := lForm.FindComponent('RepoTree');
    Assert.IsNotNull(lTree);
    Assert.AreEqual('TVirtualStringTree', lTree.ClassName);
    Assert.IsNull(lForm.FindComponent('sbRepos'));
    Assert.IsNull(lForm.FindComponent('fpRepos'));
    Assert.AreEqual(72, lForm.RepoTree.DefaultNodeHeight);
    Assert.IsFalse(toAutoChangeScale in lForm.RepoTree.TreeOptions.AutoOptions);
    Assert.AreEqual('Repositories', lForm.RepoTree.AccessibleName);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.RepositoryView_WiresHoverAndCopiesSelectedPath;
var
  lClipboardHeld: TEvent;
  lClipboardThread: TThread;
  lForm: TTestMainForm;
  lKey: Word;
  lOpened: Boolean;
  lRepoRoot: string;
  lCellRect: TRect;
begin
  lForm := TTestMainForm.Create(nil);
  lClipboardHeld := TEvent.Create(nil, True, False, '');
  lClipboardThread := nil;
  try
    Assert.IsTrue(Assigned(lForm.RepoTree.OnMouseMove));
    Assert.IsTrue(Assigned(lForm.RepoTree.OnMouseLeave));
    Assert.IsTrue(Assigned(lForm.RepoTree.OnKeyDown));

    lRepoRoot := 'C:\Repositories\Selected Repo';
    lForm.AddRepoForTest(lRepoRoot);
    lCellRect := lForm.RepoTree.GetDisplayRect(lForm.RepoTree.FocusedNode, 0, False);
    lForm.RepoTree.OnMouseMove(lForm.RepoTree, [], lCellRect.Right - 20,
      (lCellRect.Top + lCellRect.Bottom) div 2);
    Assert.AreEqual(TCursor(crHandPoint), lForm.RepoTree.Cursor);
    lForm.RepoTree.OnMouseLeave(lForm.RepoTree);
    Assert.AreEqual(TCursor(crDefault), lForm.RepoTree.Cursor);

    lOpened := False;
    lClipboardThread := TThread.CreateAnonymousThread(
      procedure
      var
        i: Integer;
      begin
        for i := 1 to 100 do
        begin
          lOpened := OpenClipboard(0);
          if lOpened then
            Break;
          TThread.Sleep(5);
        end;
        lClipboardHeld.SetEvent;
        if not lOpened then
          Exit;
        try
          TThread.Sleep(75);
        finally
          CloseClipboard;
        end;
      end);
    lClipboardThread.FreeOnTerminate := False;
    lClipboardThread.Start;
    Assert.AreEqual(TWaitResult.wrSignaled, lClipboardHeld.WaitFor(2000));
    Assert.IsTrue(lOpened, 'The test worker could not acquire the real Windows clipboard.');
    lKey := Ord('C');
    lForm.RepoTree.OnKeyDown(lForm.RepoTree, lKey, [ssCtrl]);
    Assert.AreEqual(Word(0), lKey);
    lClipboardThread.WaitFor;
    Assert.AreEqual(lRepoRoot, ReadClipboardText);
  finally
    if lClipboardThread <> nil then
    begin
      lClipboardThread.WaitFor;
      lClipboardThread.Free;
    end;
    lClipboardHeld.Free;
    lForm.Free;
  end;
end;

procedure TUiFormTests.RepositoryAccessibilityText_DescribesFailureStates;
var
  lEvent: TUiEvent;
  lForm: TTestMainForm;
  lStatus: TRepoStatus;
  lText: string;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := 'C:\Repositories\Failed Repo';
    lStatus.Branch := 'main';
    lStatus.HasOrigin := True;
    lStatus.Upstream := 'origin/main';
    lStatus.ScanFailed := True;
    lStatus.ScanError := 'scan diagnostic';
    lForm.AddStatusForTest(lStatus);

    lEvent := Default(TUiEvent);
    lEvent.Kind := TUiEventKind.uekActionResult;
    lEvent.ActionIsBulk := True;
    lEvent.ActionSucceeded := False;
    lEvent.RepoRoot := lStatus.RepoRoot;
    lEvent.ActionTag := Ord(TRepoAction.raPull);
    lEvent.ActionError := 'pull diagnostic';
    lForm.HandleEventForTest(lEvent);
    lEvent.ActionTag := Ord(TRepoAction.raPush);
    lEvent.ActionError := 'push diagnostic';
    lForm.HandleEventForTest(lEvent);
    lForm.AddStatusForTest(lStatus);

    lText := lForm.RepoTree.Text[lForm.RepoTree.GetFirst, 0];

    Assert.Contains(lText, 'Pull failed');
    Assert.Contains(lText, 'Push failed');
    Assert.Contains(lText, 'Scan failed');
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.RepositoryAccessibilityText_DescribesUnrelatedHistory;
var
  lForm: TTestMainForm;
  lStatus: TRepoStatus;
  lText: string;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := 'C:\Repositories\Unrelated Repo';
    lStatus.Branch := 'main';
    lStatus.HasOrigin := True;
    lStatus.Upstream := 'origin/main';
    lStatus.UnrelatedHistory := True;
    lStatus.Ahead := 111;
    lStatus.Behind := 122;
    lStatus.IsOutOfDate := True;
    lStatus.HasUnpushed := True;
    lStatus.SubmoduleNeedsMainFastForward := True;
    lForm.AddStatusForTest(lStatus);

    lText := lForm.RepoTree.Text[lForm.RepoTree.GetFirst, 0];

    Assert.Contains(lText, 'Unrelated history');
    Assert.IsFalse(lText.Contains('Behind:'));
    Assert.IsFalse(lText.Contains('Ahead:'));
    Assert.IsFalse(lText.Contains('No fast-forward'));
    Assert.IsFalse(lText.Contains('Clean'));
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.RepositoryPopup_OffersTortoiseGitLogWhenInstalled;
var
  lForm: TfrmMain;
  lMenuItem: TComponent;
begin
  lForm := TfrmMain.Create(nil);
  try
    lMenuItem := lForm.FindComponent('miRepoTortoiseLog');
    Assert.IsNotNull(lMenuItem);
    Assert.AreEqual('TMenuItem', lMenuItem.ClassName);
    Assert.AreEqual(TTortoiseGit.DetectExecutable <> '', TMenuItem(lMenuItem).Visible);
    Assert.IsTrue(Assigned(TMenuItem(lMenuItem).OnClick));
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.RepositoryPopup_OffersPullAndPushForEligibleRow;
var
  lForm: TTestMainForm;
  lPull, lPush: TMenuItem;
  lStatus: TRepoStatus;
  lWatch: TStopwatch;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lPull := lForm.FindComponent('miRepoPull') as TMenuItem;
    lPush := lForm.FindComponent('miRepoPush') as TMenuItem;
    Assert.IsNotNull(lPull, 'The row popup must expose Pull');
    Assert.IsNotNull(lPush, 'The row popup must expose Push');
    Assert.AreEqual('Pull', lPull.Caption);
    Assert.AreEqual('Push', lPush.Caption);
    Assert.IsTrue(Assigned(lPull.OnClick));
    Assert.IsTrue(Assigned(lPush.OnClick));

    lWatch := TStopwatch.StartNew;
    repeat
      lForm.tmrUiTimer(nil);
      if lForm.btnScan.Enabled then
        Break;
      TThread.Sleep(10);
    until lWatch.ElapsedMilliseconds >= 2000;
    Assert.IsTrue(lForm.btnScan.Enabled, 'Repository actions need completed startup');

    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := 'C:\Repositories\Action State';
    lStatus.Branch := 'main';
    lStatus.IsOutOfDate := True;
    lStatus.IsDirty := True;
    lStatus.HasProblem := True;
    lForm.AddStatusForTest(lStatus);
    lForm.RepoActionsPopup(nil);
    Assert.IsTrue(lPull.Enabled, 'A fresh behind repository can Pull');
    Assert.IsTrue(lPush.Enabled, 'A fresh dirty repository can Push');

    lStatus.IsCached := True;
    lForm.AddStatusForTest(lStatus);
    lForm.RepoActionsPopup(nil);
    Assert.IsFalse(lPull.Enabled, 'Cached status cannot authorize Pull');
    Assert.IsFalse(lPush.Enabled, 'Cached status cannot authorize Push');

    lStatus.IsCached := False;
    lStatus.ScanFailed := True;
    lForm.AddStatusForTest(lStatus);
    lForm.RepoActionsPopup(nil);
    Assert.IsFalse(lPull.Enabled, 'Failed analysis cannot authorize Pull');
    Assert.IsFalse(lPush.Enabled, 'Failed analysis cannot authorize Push');

    lStatus.ScanFailed := False;
    lStatus.UnrelatedHistory := True;
    lForm.AddStatusForTest(lStatus);
    lForm.RepoActionsPopup(nil);
    Assert.IsFalse(lPull.Enabled, 'Unrelated history cannot authorize Pull');

    lStatus.UnrelatedHistory := False;
    lStatus.IsOutOfDate := False;
    lStatus.IsDirty := False;
    lForm.AddStatusForTest(lStatus);
    lForm.RepoActionsPopup(nil);
    Assert.IsFalse(lPull.Enabled, 'A current repository has no pending Pull');
    Assert.IsFalse(lPush.Enabled, 'A clean repository has no pending Push');
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.RepositoryPopup_OffersLastOperationErrors;
var
  lForm: TfrmMain;
  lPullErrorItem: TComponent;
  lPushErrorItem: TComponent;
begin
  lForm := TfrmMain.Create(nil);
  try
    lPullErrorItem := lForm.FindComponent('miRepoLastPullError');
    lPushErrorItem := lForm.FindComponent('miRepoLastPushError');
    Assert.IsNotNull(lPullErrorItem);
    Assert.IsNotNull(lPushErrorItem);
    Assert.AreEqual('TMenuItem', lPullErrorItem.ClassName);
    Assert.AreEqual('TMenuItem', lPushErrorItem.ClassName);
    Assert.IsTrue(Assigned(TMenuItem(lPullErrorItem).OnClick));
    Assert.IsTrue(Assigned(TMenuItem(lPushErrorItem).OnClick));
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.RepositoryPopup_ShowsFullScanErrorAndRecoveryPreservesActionError;
var
  lEvent: TUiEvent;
  lForm: TTestMainForm;
  lScanErrorItem: TComponent;
  lStatus: TRepoStatus;
  lText: string;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := 'C:\Repositories\Scan Failure';
    lStatus.Branch := '(unknown)';
    lStatus.ScanFailed := True;
    lStatus.ScanError := 'fatal: invalid index'#13#10'full diagnostic detail';
    lStatus.HasProblem := True;
    lForm.AddStatusForTest(lStatus);

    lEvent := Default(TUiEvent);
    lEvent.Kind := TUiEventKind.uekActionResult;
    lEvent.ActionIsBulk := True;
    lEvent.ActionSucceeded := False;
    lEvent.RepoRoot := lStatus.RepoRoot;
    lEvent.ActionTag := Ord(TRepoAction.raPull);
    lEvent.ActionError := 'pull diagnostic';
    lForm.HandleEventForTest(lEvent);

    lForm.RepoActionsPopup(nil);
    lScanErrorItem := lForm.FindComponent('miRepoLastScanError');
    Assert.IsNotNull(lScanErrorItem);
    if lScanErrorItem = nil then
      Exit;
    Assert.IsTrue(TMenuItem(lScanErrorItem).Visible);
    Assert.IsTrue(Assigned(TMenuItem(lScanErrorItem).OnClick));
    TMenuItem(lScanErrorItem).Click;
    Assert.AreEqual(1, lForm.fImmediateErrorCount);
    Assert.AreEqual(lStatus.ScanError, lForm.fLastDialogText);

    lStatus.Branch := 'main';
    lStatus.HasOrigin := True;
    lStatus.Upstream := 'origin/main';
    lStatus.ScanFailed := False;
    lStatus.ScanError := '';
    lStatus.HasProblem := False;
    lForm.AddStatusForTest(lStatus);
    lText := lForm.RepoTree.Text[lForm.RepoTree.GetFirst, 0];
    Assert.Contains(lText, 'Pull failed');
    Assert.IsFalse(lText.Contains('Scan failed'));
    lForm.RepoActionsPopup(nil);
    Assert.IsFalse(TMenuItem(lScanErrorItem).Visible);
    Assert.IsTrue(lForm.miRepoLastPullError.Visible);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.DetailsDialog_IsScrollableCopyableAndEscapeCloseable;
var
  lCloseButton: TBitBtn;
  lCopyButton: TBitBtn;
  lDetailsMemo: TMemo;
  lDialog: TCustomForm;
  lFormClass: TPersistentClass;
begin
  lFormClass := GetClass('TfrmTextDetailsDialog');
  Assert.IsNotNull(lFormClass);
  lDialog := TFormClass(lFormClass).Create(nil);
  try
    Assert.AreEqual(TFormBorderStyle.bsSizeable, lDialog.BorderStyle);
    Assert.IsTrue(lDialog.KeyPreview);
    lDetailsMemo := lDialog.FindComponent('memDetails') as TMemo;
    lCopyButton := lDialog.FindComponent('btnCopy') as TBitBtn;
    lCloseButton := lDialog.FindComponent('btnClose') as TBitBtn;
    Assert.IsNotNull(lDetailsMemo);
    Assert.IsTrue(lDetailsMemo.ReadOnly);
    Assert.AreEqual(System.UITypes.TScrollStyle.ssBoth, lDetailsMemo.ScrollBars);
    Assert.IsNotNull(lCopyButton);
    Assert.IsTrue(Assigned(lCopyButton.OnClick));
    Assert.IsNotNull(lCloseButton);
    Assert.IsTrue(lCloseButton.Cancel);
  finally
    lDialog.Free;
  end;
end;

procedure TUiFormTests.DialogButtons_UseSharedSvgGlyphs;
var
  lCopyButton: TBitBtn;
  lDetailsCloseButton: TBitBtn;
  lDetailsForm: TCustomForm;
  lDetailsImages: TVirtualImageList;
  lFormClass: TPersistentClass;
  lHelpCloseButton: TBitBtn;
  lHelpForm: TCustomForm;
  lHelpImages: TVirtualImageList;
begin
  lFormClass := GetClass('TfrmTextDetailsDialog');
  Assert.IsNotNull(lFormClass);
  lDetailsForm := TFormClass(lFormClass).Create(nil);
  try
    lFormClass := GetClass('TfrmStatusFilterHelp');
    Assert.IsNotNull(lFormClass);
    lHelpForm := TFormClass(lFormClass).Create(nil);
    try
      lCopyButton := lDetailsForm.FindComponent('btnCopy') as TBitBtn;
      lDetailsCloseButton := lDetailsForm.FindComponent('btnClose') as TBitBtn;
      lHelpCloseButton := lHelpForm.FindComponent('btnClose') as TBitBtn;
      Assert.IsNotNull(lCopyButton.Images);
      Assert.IsNotNull(lDetailsCloseButton.Images);
      Assert.IsNotNull(lHelpCloseButton.Images);
      Assert.AreSame(lCopyButton.Images, lDetailsCloseButton.Images);
      lDetailsImages := lDetailsCloseButton.Images as TVirtualImageList;
      lHelpImages := lHelpCloseButton.Images as TVirtualImageList;
      Assert.AreEqual(lDetailsImages.GetIndexByName('copy'), lCopyButton.ImageIndex);
      Assert.AreEqual(lDetailsImages.GetIndexByName('close'), lDetailsCloseButton.ImageIndex);
      Assert.AreEqual(lHelpImages.GetIndexByName('close'), lHelpCloseButton.ImageIndex);
      Assert.AreEqual(lDetailsCloseButton.ImageIndex, lHelpCloseButton.ImageIndex);
      Assert.AreEqual(20, lDetailsImages.Width);
      Assert.AreEqual(20, lHelpImages.Width);
    finally
      lHelpForm.Free;
    end;
  finally
    lDetailsForm.Free;
  end;
end;

procedure TUiFormTests.BulkActionFailures_AreSummarizedWithoutIntermediateDialogs;
var
  lEvent: TUiEvent;
  lForm: TTestMainForm;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lEvent := Default(TUiEvent);
    lEvent.Kind := TUiEventKind.uekProgressStart;
    lEvent.ProgressMode := TProgressMode.pmDeterminate;
    lEvent.ProgressMax := 2;
    lEvent.ActionTag := Ord(TRepoAction.raPull);
    lEvent.Text := 'Pulling 0 of 2 repositories...';
    lForm.HandleEventForTest(lEvent);

    lEvent := Default(TUiEvent);
    lEvent.Kind := TUiEventKind.uekActionResult;
    lEvent.ActionTag := Ord(TRepoAction.raPull);
    lEvent.ActionIsBulk := True;
    lEvent.ActionSucceeded := False;
    lEvent.RepoRoot := 'C:\Repo A';
    lEvent.ActionError := 'fatal: first' + sLineBreak + 'secondary A';
    lForm.HandleEventForTest(lEvent);
    lEvent.RepoRoot := 'C:\Repo B';
    lEvent.ActionError := sLineBreak + 'denied' + sLineBreak + 'secondary B';
    lForm.HandleEventForTest(lEvent);

    lEvent := Default(TUiEvent);
    lEvent.Kind := TUiEventKind.uekProgressEnd;
    lEvent.ActionTag := Ord(TRepoAction.raPull);
    lEvent.Text := 'Pull finished for 2 repositories.';
    lForm.HandleEventForTest(lEvent);

    Assert.AreEqual(0, lForm.fImmediateErrorCount);
    Assert.AreEqual(1, lForm.fBulkSummaryCount);
    Assert.Contains(lForm.fLastDialogCaption, 'Pull');
    Assert.Contains(lForm.fLastDialogText, 'C:\Repo A: fatal: first');
    Assert.Contains(lForm.fLastDialogText, 'C:\Repo B: denied');
    Assert.IsFalse(lForm.fLastDialogText.Contains('secondary'));
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.ActionFailureState_PersistsAcrossRescanAndClearsIndependently;
var
  lEvent: TUiEvent;
  lForm: TTestMainForm;
  lStatus: TRepoStatus;
  lText: string;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lStatus := Default(TRepoStatus);
    lStatus.RepoRoot := 'C:\Repositories\Action State';
    lStatus.Branch := 'main';
    lStatus.HasOrigin := True;
    lStatus.Upstream := 'origin/main';
    lStatus.HasProblem := False;
    lForm.AddStatusForTest(lStatus);

    lEvent := Default(TUiEvent);
    lEvent.Kind := TUiEventKind.uekActionResult;
    lEvent.ActionIsBulk := True;
    lEvent.ActionSucceeded := False;
    lEvent.RepoRoot := lStatus.RepoRoot;
    lEvent.ActionTag := Ord(TRepoAction.raPull);
    lEvent.ActionError := 'pull failed in test';
    lForm.HandleEventForTest(lEvent);
    lEvent.ActionTag := Ord(TRepoAction.raPush);
    lEvent.ActionError := 'push failed in test';
    lForm.HandleEventForTest(lEvent);

    lForm.AddStatusForTest(lStatus);
    lText := lForm.RepoTree.Text[lForm.RepoTree.GetFirst, 0];
    Assert.Contains(lText, 'Pull failed');
    Assert.Contains(lText, 'Push failed');
    lForm.RepoActionsPopup(nil);
    Assert.IsTrue(lForm.miRepoLastPullError.Visible);
    Assert.IsTrue(lForm.miRepoLastPushError.Visible);

    lForm.cboStatusFilter.ItemIndex := Ord(TRepoFilter.rfAll);
    lForm.cboStatusFilterChange(nil);
    lEvent.ActionTag := Ord(TRepoAction.raPull);
    lEvent.ActionSucceeded := True;
    lEvent.ActionError := '';
    lForm.HandleEventForTest(lEvent);
    lForm.AddStatusForTest(lStatus);
    lText := lForm.RepoTree.Text[lForm.RepoTree.GetFirst, 0];
    Assert.IsFalse(lText.Contains('Pull failed'));
    Assert.Contains(lText, 'Push failed');
    lForm.RepoActionsPopup(nil);
    Assert.IsFalse(lForm.miRepoLastPullError.Visible);
    Assert.IsTrue(lForm.miRepoLastPushError.Visible);

    lEvent.ActionTag := Ord(TRepoAction.raPush);
    lForm.HandleEventForTest(lEvent);
    lForm.cboStatusFilter.ItemIndex := Ord(TRepoFilter.rfAttention);
    lForm.cboStatusFilterChange(nil);
    Assert.AreEqual(Cardinal(0), lForm.RepoTree.RootNodeCount);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.SingleActionFailure_ShowsImmediateDialog;
var
  lEvent: TUiEvent;
  lForm: TTestMainForm;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lEvent := Default(TUiEvent);
    lEvent.Kind := TUiEventKind.uekActionResult;
    lEvent.ActionTag := Ord(TRepoAction.raPush);
    lEvent.ActionSucceeded := False;
    lEvent.RepoRoot := 'C:\Repo';
    lEvent.ActionError := 'push failed';

    lForm.HandleEventForTest(lEvent);

    Assert.AreEqual(1, lForm.fImmediateErrorCount);
    Assert.AreEqual(0, lForm.fBulkSummaryCount);
    Assert.Contains(lForm.fLastDialogCaption, 'Push');
    Assert.AreEqual(lEvent.ActionError, lForm.fLastDialogText);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.SearchFilter_HasMnemonicAndHelpButton;
var
  lForm: TfrmMain;
  lHelp: TComponent;
begin
  lForm := TfrmMain.Create(nil);
  try
    Assert.AreEqual('Search &Filter', lForm.lblTargetName.Caption);
    Assert.AreSame(lForm.cboTargetName, lForm.lblTargetName.FocusControl);
    lHelp := lForm.FindComponent('btnFilterHelp');
    Assert.IsNotNull(lHelp);
    Assert.AreEqual('TBitBtn', lHelp.ClassName);
    Assert.AreEqual('?', TBitBtn(lHelp).Caption);
    Assert.IsTrue(Assigned(TBitBtn(lHelp).OnClick));
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.SearchFilter_ShowsMatchedAndDiscoveredCounts;
var
  lForm: TTestMainForm;
begin
  lForm := TTestMainForm.Create(nil);
  try
    lForm.cboTargetName.Text := 'alpha !archive';
    lForm.SetSearchFilterCounts(30, 600, True);
    Assert.AreEqual('Search &Filter (30 of 600)', lForm.lblTargetName.Caption);

    lForm.cboTargetName.Text := '';
    lForm.SetSearchFilterCounts(30, 600, True);
    Assert.AreEqual('Search &Filter', lForm.lblTargetName.Caption);

    lForm.cboTargetName.Text := '*';
    lForm.SetSearchFilterCounts(0, 0, False);
    Assert.AreEqual('Search &Filter', lForm.lblTargetName.Caption);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.StatusFilter_OffersActionableStatesAndHelp;
var
  lForm: TfrmMain;
  lHelp: TComponent;
begin
  lForm := TfrmMain.Create(nil);
  try
    Assert.AreEqual(12, lForm.cboStatusFilter.Items.Count);
    Assert.AreEqual('Needs attention (0)', lForm.cboStatusFilter.Items[0]);
    Assert.AreEqual('Operation failed (0)', lForm.cboStatusFilter.Items[1]);
    Assert.AreEqual('Scan failed (0)', lForm.cboStatusFilter.Items[2]);
    Assert.AreEqual('Unrelated history (0)', lForm.cboStatusFilter.Items[3]);
    Assert.AreEqual('Safe pull: clean and behind (0)', lForm.cboStatusFilter.Items[4]);
    Assert.AreEqual('Behind, not ahead (0)', lForm.cboStatusFilter.Items[5]);
    Assert.AreEqual('Diverged (0)', lForm.cboStatusFilter.Items[6]);
    Assert.AreEqual('Ahead, not behind (0)', lForm.cboStatusFilter.Items[7]);
    Assert.AreEqual('Dirty (0)', lForm.cboStatusFilter.Items[8]);
    Assert.AreEqual('Detached (0)', lForm.cboStatusFilter.Items[9]);
    Assert.AreEqual('No issues (0)', lForm.cboStatusFilter.Items[10]);
    Assert.AreEqual('All (0)', lForm.cboStatusFilter.Items[11]);
    lHelp := lForm.FindComponent('btnStatusFilterHelp');
    Assert.IsNotNull(lHelp);
    Assert.AreEqual('TBitBtn', lHelp.ClassName);
    Assert.AreEqual('?', TBitBtn(lHelp).Caption);
    Assert.IsTrue(Assigned(TBitBtn(lHelp).OnClick));
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.StatusFilterHelp_IsModalReadyAndExplainsEveryState;
var
  lCloseButton: TBitBtn;
  lFormClass: TPersistentClass;
  lHelpForm: TCustomForm;
  lHelpMemo: TMemo;
begin
  lFormClass := GetClass('TfrmStatusFilterHelp');
  Assert.IsNotNull(lFormClass);
  lHelpForm := TFormClass(lFormClass).Create(nil);
  try
    Assert.AreEqual(TFormBorderStyle.bsDialog, lHelpForm.BorderStyle);
    Assert.IsTrue(lHelpForm.KeyPreview);
    lHelpMemo := lHelpForm.FindComponent('memStatusFilterHelp') as TMemo;
    lCloseButton := lHelpForm.FindComponent('btnClose') as TBitBtn;
    Assert.IsNotNull(lHelpMemo);
    Assert.IsTrue(lHelpMemo.ReadOnly);
    Assert.Contains(lHelpMemo.Text, 'Needs attention');
    Assert.Contains(lHelpMemo.Text, 'Operation failed');
    Assert.Contains(lHelpMemo.Text, 'Scan failed');
    Assert.Contains(lHelpMemo.Text, 'Unrelated history');
    Assert.Contains(lHelpMemo.Text, 'no common ancestor');
    Assert.Contains(lHelpMemo.Text, 'Pull all');
    Assert.Contains(lHelpMemo.Text, 'Safe pull: clean and behind');
    Assert.Contains(lHelpMemo.Text, 'Behind, not ahead');
    Assert.Contains(lHelpMemo.Text, 'includes dirty and detached repositories');
    Assert.Contains(lHelpMemo.Text, 'Diverged');
    Assert.Contains(lHelpMemo.Text, 'Ahead, not behind');
    Assert.Contains(lHelpMemo.Text, 'Dirty');
    Assert.Contains(lHelpMemo.Text, 'Detached');
    Assert.Contains(lHelpMemo.Text, 'No issues');
    Assert.Contains(lHelpMemo.Text, 'All');
    Assert.IsNotNull(lCloseButton);
    Assert.IsTrue(lCloseButton.Cancel);
  finally
    lHelpForm.Free;
  end;
end;

procedure TUiFormTests.BulkActions_ExplainVisibleScopeWithBalloonHints;
var
  lBalloonHint: TComponent;
  lForm: TfrmMain;
begin
  lForm := TfrmMain.Create(nil);
  try
    lBalloonHint := lForm.FindComponent('BalloonHint');
    Assert.IsNotNull(lBalloonHint);
    Assert.AreEqual('TBalloonHint', lBalloonHint.ClassName);
    Assert.AreSame(lBalloonHint, lForm.btnPullVisible.CustomHint);
    Assert.AreSame(lBalloonHint, lForm.btnPushVisible.CustomHint);
    Assert.AreSame(lBalloonHint, lForm.cboTargetName.CustomHint);
    Assert.AreSame(lBalloonHint, lForm.cboStatusFilter.CustomHint);
    Assert.IsTrue(lForm.btnPullVisible.ShowHint);
    Assert.IsTrue(lForm.btnPushVisible.ShowHint);
    Assert.IsTrue(lForm.cboTargetName.ShowHint);
    Assert.IsTrue(lForm.cboStatusFilter.ShowHint);
    Assert.AreEqual('Runs Pull for every visible repository with a Pull action. ' +
      'Search Filter and Status Filter define the visible subset.', lForm.btnPullVisible.Hint);
    Assert.AreEqual('Runs Push for every visible repository with a Push action. ' +
      'Search Filter and Status Filter define the visible subset.', lForm.btnPushVisible.Hint);
    Assert.Contains(lForm.cboTargetName.Hint, 'Only matching repositories are shown');
    Assert.Contains(lForm.cboStatusFilter.Hint, 'visible in this status');
  finally
    lForm.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUiFormTests);

end.
