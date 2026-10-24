unit TestFolderTreeFrame;

interface

uses
  System.Classes, System.Diagnostics, System.IOUtils, System.SysUtils, System.Types,
  Winapi.Messages, Winapi.Windows,
  Vcl.ComCtrls, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.Menus,
  DUnitX.TestFramework,
  UFolderSelection, UFolderTreeFrame;

type
  TRecreateControlAccess = class(TWinControl);

  TPopupTestHostForm = class(TForm)
  protected
    procedure CreateParams(var aParams: TCreateParams); override;
    procedure CMShowingChanged(var aMessage: TMessage); message CM_SHOWINGCHANGED;
  public
    procedure SetFocus; override;
  end;

  TTestFolderTreeFrame = class(TFolderTreeFrame)
  public
    function FindNodeForTest(const aPath: string): TTreeNode;
    function NodePathForTest(const aNode: TTreeNode): string;
    procedure RequestChildrenForTest(const aPath: string);
    procedure CancelEnumerationForTest;
    property EnumerationBusy: Boolean read GetEnumerationBusy;
    property PendingEnumerationCount: Integer read GetPendingEnumerationCount;
  end;

  [TestFixture]
  TFolderTreeFrameTests = class
  private
    fForm: TForm;
    fFrame: TTestFolderTreeFrame;
    fTempRoot: string;
    fChangeCount: Integer;
    fRecreateException: string;
    fPopupTimer: TTimer;
    fPopupCount: Integer;
    fDiscoverCount: Integer;
    fDiscoveredPath: string;
    fPopupSelection: TTreeNode;
    fPopupAvailabilityMode: Integer;
    fPopupInitiallyEnabled: Boolean;
    fPopupDisabledNativeState: Cardinal;
    fPopupEnabledNativeState: Cardinal;
    fPopupRejectedCount: Integer;
    fNativePopupAction: Boolean;
    fNativePopupKeysPosted: Boolean;
    fNativePopupTimedOut: Boolean;
    procedure CaptureRecreateException(aSender: TObject; E: Exception);
    procedure PopupOpened(aSender: TObject);
    procedure InvokePopupAction(aSender: TObject);
    procedure DiscoverHere(aSender: TObject; const aPath: string);
    procedure SendPointerContext(const aNode: TTreeNode);
    class function Rule(const aPath: string; const aIncluded: Boolean): TFolderSelectionRule; static;
    procedure SelectionChanged(aSender: TObject);
    procedure WaitForEnumeration;
    procedure CreateJunction(const aLinkPath, aTargetPath: string);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure NativeTree_UsesCheckboxesAndPartialState;
    [TestCase('Tree', 'False')]
    [TestCase('AncestorFrame', 'True')]
    procedure NativeRecreation_PreservesNodeIdentityRulesAndCheckboxBehavior(const aAncestor: Boolean);
    [Test]
    procedure DeferredNativeRecreation_DestroyWithoutRestoringHandle;
    [Test]
    procedure Initialize_RetainsDisconnectedRulesAndKnownAncestors;
    [Test]
    procedure Space_OverridesDescendantExceptionsOnce;
    [Test]
    procedure Navigation_PreservesRulesAndPublishesNoSelectionChange;
    [Test]
    procedure Expansion_LoadsOnlyImmediateChildrenAsynchronously;
    [Test]
    procedure Enumeration_QueueIsBoundedAndCancellationOwnsWorkers;
    [Test]
    procedure RestoredExpansion_LoadsImmediateChildrenWithoutChangingRules;
    [Test]
    procedure RestoredExpansion_BackpressureDoesNotDropSavedPaths;
    [Test]
    procedure ReparseChild_IsVisibleButDoesNotEnumerateItsTarget;
    [Test]
    procedure UnavailableUNC_RetainsKnownNodeAndSupportsOwnedCancellation;
    [Test]
    procedure Popup_PointerCapturesActualNodeAndPreservesChecks;
    [TestCase('Pointer', 'False')]
    [TestCase('Keyboard', 'True')]
    procedure Popup_NativeCommandDiscoversCapturedNodeOnce(const aKeyboard: Boolean);
    [Test]
    procedure Popup_KeyboardFreezesSelectedNodeForItsLifetime;
    [TestCase('Long path', 'False')]
    [TestCase('Long path scrolled', 'True')]
    procedure Popup_KeyboardLongPathUsesSelectedNode(const aScrolled: Boolean);
    [Test]
    procedure Popup_BlankSpaceCannotReusePriorTarget;
    [Test]
    procedure Popup_DisabledAvailabilityBlocksUntilReenabled;
    [Test]
    procedure Popup_AvailabilityChangesUpdateOpenMenuAndGuardDispatch;
  end;

implementation

procedure TPopupTestHostForm.CreateParams(var aParams: TCreateParams);
begin
  inherited;
  aParams.ExStyle := aParams.ExStyle or WS_EX_NOACTIVATE;
end;

procedure TPopupTestHostForm.CMShowingChanged(var aMessage: TMessage);
begin
  if Showing then
    ShowWindow(Handle, SW_SHOWNOACTIVATE)
  else
    ShowWindow(Handle, SW_HIDE);
end;

procedure TPopupTestHostForm.SetFocus;
begin
  // Popup-target tests must not activate a window on our interactive desktop.
  // Native menu/control messages remain real; actual keyboard focus is separate live proof.
end;

function TTestFolderTreeFrame.FindNodeForTest(const aPath: string): TTreeNode;
begin
  Result := FindNode(aPath);
end;

function TTestFolderTreeFrame.NodePathForTest(const aNode: TTreeNode): string;
begin
  Result := NodePath(aNode);
end;

procedure TTestFolderTreeFrame.RequestChildrenForTest(const aPath: string);
begin
  RequestChildren(aPath);
end;

procedure TTestFolderTreeFrame.CancelEnumerationForTest;
begin
  CancelEnumeration;
end;

procedure TFolderTreeFrameTests.NativeTree_UsesCheckboxesAndPartialState;
begin
  Assert.IsTrue(fFrame.FolderTree.CheckBoxes);
  Assert.IsTrue(TCheckStyle.csPartial in fFrame.FolderTree.CheckStyles);
  Assert.IsTrue(fFrame.FolderTree.Align = TAlign.alClient);
end;

procedure TFolderTreeFrameTests.DeferredNativeRecreation_DestroyWithoutRestoringHandle;
var
  lRules, lAfterRules: TArray<TFolderSelectionRule>;
  i: Integer;
begin
  lRules := [Rule('C:\tree-fixture', True), Rule('C:\tree-fixture\child', False)];
  fFrame.Initialize(lRules, []);
  Assert.IsTrue(fFrame.FolderTree.HandleAllocated);
  Assert.IsNotNull(fFrame.FindNodeForTest(lRules[0].Path).Data);
  TRecreateControlAccess(fFrame.FolderTree).RecreateWnd;
  Assert.IsFalse(fFrame.FolderTree.HandleAllocated,
    'Hidden parent deliberately leaves native restoration deferred');
  lAfterRules := fFrame.Rules;
  Assert.AreEqual(Length(lRules), Length(lAfterRules));
  for i := 0 to High(lRules) do
  begin
    Assert.AreEqual(lRules[i].Path, lAfterRules[i].Path);
    Assert.AreEqual(lRules[i].Included, lAfterRules[i].Included);
  end;
  Assert.AreEqual(0, fChangeCount);
  // T050: TearDown must free retained data without creating the handle again.
  // The runner's named TFolderNodeData shutdown leak report is the lifetime proof.
end;

procedure TFolderTreeFrameTests.CaptureRecreateException(aSender: TObject; E: Exception);
begin
  // T050: retain a native WndProc exception as a test failure without a modal dialog.
  if fRecreateException = '' then
    fRecreateException := E.ClassName + ': ' + E.Message;
end;

procedure TFolderTreeFrameTests.NativeRecreation_PreservesNodeIdentityRulesAndCheckboxBehavior(
  const aAncestor: Boolean);
var
  lRules, lAfterRules: TArray<TFolderSelectionRule>;
  lOldExceptionHandler: TExceptionEvent;
  lNode, lParent: TTreeNode;
  lPath: string;
  lNodeCount: Integer;
  i: Integer;
begin
  lRules := [Rule('C:\tree-fixture', True), Rule('C:\tree-fixture\child', False),
    Rule('C:\tree-fixture\child\grandchild', True)];
  fFrame.Initialize(lRules, []);
  lNodeCount := fFrame.FolderTree.Items.Count;
  fRecreateException := '';
  lOldExceptionHandler := Application.OnException;
  Application.OnException := CaptureRecreateException;
  try
    if aAncestor then
      TRecreateControlAccess(fFrame).RecreateWnd
    else
      TRecreateControlAccess(fFrame.FolderTree).RecreateWnd;
    // Our hidden parent defers creation; complete the native restore before assertions.
    fFrame.FolderTree.HandleNeeded;
  finally
    Application.OnException := lOldExceptionHandler;
  end;
  Assert.AreEqual('', fRecreateException, 'Native recreation must not raise a dispatched exception');
  Assert.AreEqual(lNodeCount, fFrame.FolderTree.Items.Count);
  Assert.AreEqual(0, fChangeCount, 'Restoring native nodes must not edit selection rules');
  lParent := nil;
  for i := 0 to fFrame.FolderTree.Items.Count - 1 do
  begin
    // Enumerate live native nodes; never dereference a cached node before identity agrees.
    lNode := fFrame.FolderTree.Items[i];
    Assert.IsNotNull(lNode.Data, 'Recreated node must retain its path data');
    lPath := fFrame.NodePathForTest(lNode);
    Assert.IsTrue(lPath <> '', 'Recreated path data must remain readable');
    Assert.IsTrue(fFrame.FindNodeForTest(lPath) = lNode,
      'Path index must reference the recreated live node: ' + lPath);
    if lPath = NormalizeSelectionPath(lRules[0].Path) then
      lParent := lNode;
  end;
  lAfterRules := fFrame.Rules;
  Assert.AreEqual(Length(lRules), Length(lAfterRules));
  for i := 0 to High(lRules) do
  begin
    Assert.AreEqual(lRules[i].Path, lAfterRules[i].Path);
    Assert.AreEqual(lRules[i].Included, lAfterRules[i].Included);
  end;
  Assert.IsNotNull(lParent);
  Assert.AreEqual(Integer(TNodeCheckState.ncsPartial), Integer(lParent.CheckState));
  fFrame.FolderTree.Selected := lParent;
  fFrame.FolderTree.Perform(WM_KEYDOWN, VK_SPACE, 0);
  fFrame.FolderTree.Perform(WM_KEYUP, VK_SPACE, 0);
  Assert.AreEqual(1, fChangeCount, 'Space after recreation must toggle once');
  Assert.AreEqual(1, Length(fFrame.Rules));
  Assert.IsTrue(EvaluateFolderSelection(lRules[1].Path, fFrame.Rules));
  Assert.AreEqual(Integer(TNodeCheckState.ncsChecked), Integer(lParent.CheckState));
end;

class function TFolderTreeFrameTests.Rule(const aPath: string;
  const aIncluded: Boolean): TFolderSelectionRule;
begin
  Result.Path := aPath;
  Result.Included := aIncluded;
end;

procedure TFolderTreeFrameTests.Setup;
begin
  fForm := TPopupTestHostForm.CreateNew(nil);
  fFrame := TTestFolderTreeFrame.Create(fForm);
  fFrame.Parent := fForm;
  fFrame.FolderTree.HandleNeeded;
  fFrame.OnSelectionChanged := SelectionChanged;
  fChangeCount := 0;
  fTempRoot := '';
  fPopupTimer := TTimer.Create(fForm);
  fPopupTimer.Enabled := False;
  fPopupTimer.Interval := 25;
  fPopupTimer.OnTimer := InvokePopupAction;
  fFrame.FolderPopup.OnPopup := PopupOpened;
  fFrame.OnDiscoverHere := DiscoverHere;
  fPopupCount := 0;
  fDiscoverCount := 0;
  fDiscoveredPath := '';
  fPopupSelection := nil;
  fPopupAvailabilityMode := 0;
  fPopupInitiallyEnabled := False;
  fPopupDisabledNativeState := 0;
  fPopupEnabledNativeState := 0;
  fPopupRejectedCount := 0;
  fNativePopupAction := False;
  fNativePopupKeysPosted := False;
  fNativePopupTimedOut := False;
end;

procedure TFolderTreeFrameTests.TearDown;
begin
  fForm.Free;
  fFrame := nil;
  if (fTempRoot <> '') and TDirectory.Exists(fTempRoot) then
    TDirectory.Delete(fTempRoot, True);
end;

procedure TFolderTreeFrameTests.SelectionChanged(aSender: TObject);
begin
  Inc(fChangeCount);
end;

procedure TFolderTreeFrameTests.WaitForEnumeration;
var
  lWatch: TStopwatch;
begin
  lWatch := TStopwatch.StartNew;
  while fFrame.EnumerationBusy and (lWatch.ElapsedMilliseconds < 5000) do
  begin
    Application.ProcessMessages;
    Sleep(1);
  end;
  Assert.IsFalse(fFrame.EnumerationBusy, 'Enumeration must complete within the fixture deadline');
end;

procedure TFolderTreeFrameTests.Initialize_RetainsDisconnectedRulesAndKnownAncestors;
var
  lRules: TArray<TFolderSelectionRule>;
  lNode: TTreeNode;
begin
  lRules := [Rule('\\repopulse-unavailable.invalid\share\team\repo', True)];
  fFrame.Initialize(lRules, ['\\repopulse-unavailable.invalid\share\team']);
  lNode := fFrame.FindNodeForTest('\\repopulse-unavailable.invalid\share\team\repo');
  Assert.IsNotNull(lNode, 'Persisted unavailable path must appear without enumeration');
  Assert.IsNotNull(lNode.Parent, 'Known path ancestors must appear');
  Assert.AreEqual('\\repopulse-unavailable.invalid\share\team', fFrame.NodePathForTest(lNode.Parent));
  Assert.AreEqual(1, Length(fFrame.Rules));
  lRules[0].Included := False;
  Assert.IsTrue(fFrame.Rules[0].Included, 'Initialize must own a snapshot');
  lRules := fFrame.Rules;
  lRules[0].Included := False;
  Assert.IsTrue(fFrame.Rules[0].Included, 'Rules getter must return a snapshot');
  Assert.AreEqual(0, fChangeCount);
end;

procedure TFolderTreeFrameTests.Space_OverridesDescendantExceptionsOnce;
var
  lNode: TTreeNode;
begin
  fFrame.Initialize([Rule('C:\tree-fixture', True), Rule('C:\tree-fixture\child', False),
    Rule('C:\tree-fixture\child\grandchild', True)], []);
  lNode := fFrame.FindNodeForTest('C:\tree-fixture');
  Assert.IsNotNull(lNode);
  Assert.AreEqual(Integer(TNodeCheckState.ncsPartial), Integer(lNode.CheckState));
  fFrame.FolderTree.Selected := lNode;
  fFrame.FolderTree.Perform(WM_KEYDOWN, VK_SPACE, 0);
  fFrame.FolderTree.Perform(WM_KEYUP, VK_SPACE, 0);
  Assert.AreEqual(1, Length(fFrame.Rules), 'Checking mixed parent removes descendant exceptions');
  Assert.IsTrue(EvaluateFolderSelection('C:\tree-fixture\child', fFrame.Rules));
  Assert.AreEqual(1, fChangeCount, 'Space must toggle once');
  Assert.AreEqual(Integer(TNodeCheckState.ncsChecked), Integer(lNode.CheckState));
end;

procedure TFolderTreeFrameTests.Navigation_PreservesRulesAndPublishesNoSelectionChange;
var
  lRules: TArray<TFolderSelectionRule>;
  lNode: TTreeNode;
begin
  lRules := [Rule('C:\tree-fixture', True), Rule('C:\tree-fixture\child', False)];
  fFrame.Initialize(lRules, []);
  lNode := fFrame.FindNodeForTest('C:\tree-fixture');
  Assert.IsNotNull(lNode);
  fFrame.FolderTree.Selected := lNode;
  fFrame.FolderTree.Perform(WM_KEYDOWN, VK_RIGHT, 0);
  fFrame.FolderTree.Selected := fFrame.FindNodeForTest('C:\tree-fixture\child');
  Assert.AreEqual(2, Length(fFrame.Rules));
  Assert.IsTrue(EvaluateFolderSelection('C:\tree-fixture', fFrame.Rules));
  Assert.IsFalse(EvaluateFolderSelection('C:\tree-fixture\child', fFrame.Rules));
  Assert.AreEqual(0, fChangeCount);
  Assert.AreEqual(NormalizeSelectionPath('C:\tree-fixture\child'), fFrame.ContextPath);
end;

procedure TFolderTreeFrameTests.Expansion_LoadsOnlyImmediateChildrenAsynchronously;
var
  lChild, lGrandchild: string;
begin
  fTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseTree-' + TPath.GetRandomFileName);
  lChild := TPath.Combine(fTempRoot, 'child');
  lGrandchild := TPath.Combine(lChild, 'grandchild');
  TDirectory.CreateDirectory(lGrandchild);
  fFrame.Initialize([Rule(fTempRoot, True)], []);
  Assert.IsNull(fFrame.FindNodeForTest(lChild), 'Initialization must not enumerate');
  fFrame.RequestChildrenForTest(fTempRoot);
  Assert.IsTrue(fFrame.EnumerationBusy, 'Delivery must happen asynchronously');
  Assert.IsNull(fFrame.FindNodeForTest(lChild), 'Request must not deliver synchronously');
  WaitForEnumeration;
  Assert.IsNotNull(fFrame.FindNodeForTest(lChild));
  Assert.IsNull(fFrame.FindNodeForTest(lGrandchild), 'Expansion must not recurse');
  Assert.AreEqual(0, fChangeCount);
end;

procedure TFolderTreeFrameTests.Enumeration_QueueIsBoundedAndCancellationOwnsWorkers;
var
  lRules: TArray<TFolderSelectionRule>;
  lPath: string;
  i: Integer;
begin
  fTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseTreeQueue-' + TPath.GetRandomFileName);
  SetLength(lRules, cFolderEnumerationQueueCapacity * 3);
  for i := 0 to High(lRules) do
  begin
    lPath := TPath.Combine(fTempRoot, IntToStr(i));
    TDirectory.CreateDirectory(lPath);
    lRules[i] := Rule(lPath, True);
  end;
  fFrame.Initialize(lRules, []);
  for i := 0 to High(lRules) do
    fFrame.RequestChildrenForTest(lRules[i].Path);
  Assert.IsTrue(fFrame.PendingEnumerationCount > 0, 'Requests must enter the owned queue');
  Assert.IsTrue(fFrame.PendingEnumerationCount <= cFolderEnumerationQueueCapacity,
    'Request and delivery backlog must stay bounded');
  fFrame.CancelEnumerationForTest;
  Assert.IsFalse(fFrame.EnumerationBusy, 'Cancel returns after owned worker exits');
  Assert.AreEqual(0, fFrame.PendingEnumerationCount);
  fForm.Free;
  fForm := nil;
  fFrame := nil;
  Application.ProcessMessages;
end;

procedure TFolderTreeFrameTests.RestoredExpansion_LoadsImmediateChildrenWithoutChangingRules;
var
  lChild, lGrandchild: string;
  lExpanded: TArray<string>;
begin
  fTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseTreeRestore-' + TPath.GetRandomFileName);
  lChild := TPath.Combine(fTempRoot, 'child');
  lGrandchild := TPath.Combine(lChild, 'grandchild');
  TDirectory.CreateDirectory(lGrandchild);
  fFrame.Initialize([Rule(fTempRoot, True)], [fTempRoot]);
  Assert.IsNull(fFrame.FindNodeForTest(lChild), 'Restoration must deliver children asynchronously');
  lExpanded := fFrame.ExpandedPaths;
  Assert.AreEqual(1, Length(lExpanded));
  Assert.AreEqual(NormalizeSelectionPath(fTempRoot), lExpanded[0]);
  WaitForEnumeration;
  Assert.IsNotNull(fFrame.FindNodeForTest(lChild), 'Saved expansion must load without collapse/re-expand');
  Assert.IsTrue(fFrame.FindNodeForTest(fTempRoot).Expanded, 'Loaded saved branch must remain expanded');
  Assert.IsNull(fFrame.FindNodeForTest(lGrandchild), 'Restoration must not recurse into unsaved children');
  Assert.AreEqual(1, Length(fFrame.Rules));
  Assert.IsTrue(EvaluateFolderSelection(lGrandchild, fFrame.Rules));
  Assert.AreEqual(0, fChangeCount);
end;

procedure TFolderTreeFrameTests.RestoredExpansion_BackpressureDoesNotDropSavedPaths;
var
  lExpanded: TArray<string>;
  lMarker: string;
  i: Integer;
begin
  fTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseTreeRestoreQueue-' + TPath.GetRandomFileName);
  SetLength(lExpanded, cFolderEnumerationQueueCapacity + 3);
  for i := 0 to High(lExpanded) do
  begin
    lExpanded[i] := TPath.Combine(fTempRoot, IntToStr(i));
    TDirectory.CreateDirectory(TPath.Combine(lExpanded[i], 'marker'));
  end;
  fFrame.Initialize([Rule(fTempRoot, True)], lExpanded);
  Assert.AreEqual(Length(lExpanded), Length(fFrame.ExpandedPaths));
  Assert.IsTrue(fFrame.PendingEnumerationCount <= cFolderEnumerationQueueCapacity);
  WaitForEnumeration;
  for i := 0 to High(lExpanded) do
  begin
    lMarker := TPath.Combine(lExpanded[i], 'marker');
    Assert.IsNotNull(fFrame.FindNodeForTest(lMarker), 'Saved branch was dropped: ' + lExpanded[i]);
  end;
  Assert.AreEqual(Length(lExpanded), Length(fFrame.ExpandedPaths));
  Assert.AreEqual(1, Length(fFrame.Rules));
  Assert.AreEqual(0, fChangeCount);
end;

procedure TFolderTreeFrameTests.CreateJunction(const aLinkPath, aTargetPath: string);
var
  lCommand, lCommandProcessor: string;
  lStartup: TStartupInfo;
  lProcess: TProcessInformation;
  lWait, lExitCode: Cardinal;
begin
  Assert.IsFalse(aLinkPath.Contains('%') or aTargetPath.Contains('%'),
    'Junction fixture paths must not contain command-processor expansion tokens');
  lCommandProcessor := GetEnvironmentVariable('ComSpec');
  lCommand := '"' + lCommandProcessor + '" /d /v:off /c mklink /J "' + aLinkPath + '" "' + aTargetPath + '"';
  UniqueString(lCommand);
  lStartup := Default(TStartupInfo);
  lStartup.cb := SizeOf(lStartup);
  lProcess := Default(TProcessInformation);
  Assert.IsTrue(CreateProcess(PChar(lCommandProcessor), PChar(lCommand), nil, nil, False,
    CREATE_NO_WINDOW, nil, nil, lStartup, lProcess), 'Cannot start real junction fixture command');
  try
    lWait := WaitForSingleObject(lProcess.hProcess, 5000);
    if lWait <> WAIT_OBJECT_0 then
    begin
      // This helper owns this exact child process; stop it before releasing fixture paths.
      TerminateProcess(lProcess.hProcess, 1);
      WaitForSingleObject(lProcess.hProcess, 5000);
      Assert.Fail('Real junction creation did not finish within five seconds');
    end;
    Assert.IsTrue(GetExitCodeProcess(lProcess.hProcess, lExitCode));
    Assert.AreEqual(Cardinal(0), lExitCode, 'mklink /J must succeed; no privilege-based skip');
  finally
    CloseHandle(lProcess.hThread);
    CloseHandle(lProcess.hProcess);
  end;
end;

procedure TFolderTreeFrameTests.ReparseChild_IsVisibleButDoesNotEnumerateItsTarget;
var
  lBrowse, lTarget, lJunction, lMarker: string;
  lNode: TTreeNode;
  lAttributes: Cardinal;
begin
  fTempRoot := TPath.Combine(TPath.GetTempPath, 'RepoPulseTreeJunction-' + TPath.GetRandomFileName);
  lBrowse := TPath.Combine(fTempRoot, 'browse');
  lTarget := TPath.Combine(fTempRoot, 'target');
  lJunction := TPath.Combine(lBrowse, 'junction');
  lMarker := TPath.Combine(lTarget, 'must-not-follow');
  TDirectory.CreateDirectory(lBrowse);
  TDirectory.CreateDirectory(lMarker);
  try
    CreateJunction(lJunction, lTarget);
    lAttributes := GetFileAttributes(PChar(lJunction));
    Assert.IsTrue((lAttributes <> INVALID_FILE_ATTRIBUTES) and
      ((lAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0), 'Fixture must be a real reparse point');
    fFrame.Initialize([Rule(lBrowse, True)], []);
    fFrame.RequestChildrenForTest(lBrowse);
    WaitForEnumeration;
    lNode := fFrame.FindNodeForTest(lJunction);
    Assert.IsNotNull(lNode, 'Junction must remain visible');
    lNode.Expand(False);
    fFrame.RequestChildrenForTest(lJunction);
    Assert.IsFalse(fFrame.EnumerationBusy, 'Reparse node must not start target enumeration');
    Assert.IsNull(fFrame.FindNodeForTest(TPath.Combine(lJunction, 'must-not-follow')));
    Assert.AreEqual(0, fChangeCount);
  finally
    fFrame.CancelEnumerationForTest;
    if GetFileAttributes(PChar(lJunction)) <> INVALID_FILE_ATTRIBUTES then
      if not Winapi.Windows.RemoveDirectory(PChar(lJunction)) then
      begin
        // Never recursively clean a fixture while its junction is still present.
        fTempRoot := '';
        Assert.Fail('Cannot remove junction safely; fixture retained at ' + lJunction);
      end;
  end;
  Assert.IsTrue(TDirectory.Exists(lMarker), 'Removing the junction must preserve its target');
end;

procedure TFolderTreeFrameTests.UnavailableUNC_RetainsKnownNodeAndSupportsOwnedCancellation;
var
  lPath: string;
  lNode: TTreeNode;
  lWatch: TStopwatch;
begin
  lPath := '\\localhost\RepoPulseMissing-' + TPath.GetRandomFileName + '\known';
  fFrame.Initialize([Rule(lPath, True)], []);
  lNode := fFrame.FindNodeForTest(lPath);
  Assert.IsNotNull(lNode);
  lWatch := TStopwatch.StartNew;
  fFrame.RequestChildrenForTest(lPath);
  Assert.IsTrue(lWatch.ElapsedMilliseconds < 1000, 'UNC request must return without waiting for IO');
  Assert.IsTrue(fFrame.EnumerationBusy, 'UNC completion must use asynchronous delivery');
  WaitForEnumeration;
  Assert.IsTrue(lNode = fFrame.FindNodeForTest(lPath), 'Unavailable path must remain in the tree');
  Assert.IsTrue(string(fFrame.StatusText.Caption).Contains('Folder unavailable:'), 'Failure must be visible');
  Assert.IsTrue(string(fFrame.StatusText.Caption).Contains(NormalizeSelectionPath(lPath)));
  Assert.IsTrue(EvaluateFolderSelection(lPath, fFrame.Rules));
  fFrame.RequestChildrenForTest(lPath);
  lWatch := TStopwatch.StartNew;
  fFrame.CancelEnumerationForTest;
  Assert.IsTrue(lWatch.ElapsedMilliseconds < 5000, 'Local missing-share cancellation exceeded five seconds');
  Assert.IsFalse(fFrame.EnumerationBusy);
  Assert.AreEqual(0, fFrame.PendingEnumerationCount);
  Assert.AreEqual(0, fChangeCount);
  fForm.Free;
  fForm := nil;
  fFrame := nil;
  Application.ProcessMessages;
end;

procedure TFolderTreeFrameTests.PopupOpened(aSender: TObject);
begin
  Inc(fPopupCount);
  fPopupTimer.Enabled := True;
end;

procedure TFolderTreeFrameTests.InvokePopupAction(aSender: TObject);
begin
  fPopupTimer.Enabled := False;
  if fNativePopupAction then
  begin
    if fNativePopupKeysPosted then
    begin
      fNativePopupTimedOut := True;
      EndMenu;
      Exit;
    end;
    if Assigned(fPopupSelection) then
      fFrame.FolderTree.Selected := fPopupSelection;
    fPopupInitiallyEnabled := fFrame.DiscoverHereItem.Enabled;
    // T055: target only our thread's VCL popup owner. USER32 selects the item
    // and produces WM_COMMAND; do not call Click or synthesize WM_COMMAND.
    fNativePopupKeysPosted := PostMessage(PopupList.Window, WM_KEYDOWN, VK_DOWN, 1);
    fNativePopupKeysPosted := PostMessage(PopupList.Window, WM_KEYDOWN, VK_RETURN, 1) and
      fNativePopupKeysPosted;
    if not fNativePopupKeysPosted then
    begin
      EndMenu;
      Exit;
    end;
    fPopupTimer.Interval := 1000;
    fPopupTimer.Enabled := True;
    Exit;
  end;
  try
    if Assigned(fPopupSelection) then
      fFrame.FolderTree.Selected := fPopupSelection;
    if fPopupAvailabilityMode <> 0 then
    begin
      fPopupInitiallyEnabled := fFrame.DiscoverHereItem.Enabled;
      if fPopupAvailabilityMode = 2 then
        fFrame.DiscoveryEnabled := False;
      fPopupDisabledNativeState := GetMenuState(fFrame.FolderPopup.Handle,
        fFrame.DiscoverHereItem.Command, MF_BYCOMMAND);
      if fPopupAvailabilityMode = 2 then
      begin
        // Exercise the dispatch guard independently of TMenuItem.Click's Enabled check.
        fFrame.DiscoverHereItemClick(fFrame.DiscoverHereItem);
        fPopupRejectedCount := fDiscoverCount;
        fFrame.DiscoveryEnabled := True;
        fPopupEnabledNativeState := GetMenuState(fFrame.FolderPopup.Handle,
          fFrame.DiscoverHereItem.Command, MF_BYCOMMAND);
      end;
    end;
    fFrame.DiscoverHereItem.Click;
  finally
    EndMenu;
  end;
end;

procedure TFolderTreeFrameTests.DiscoverHere(aSender: TObject; const aPath: string);
begin
  Inc(fDiscoverCount);
  fDiscoveredPath := aPath;
end;

procedure TFolderTreeFrameTests.SendPointerContext(const aNode: TTreeNode);
var
  lRect: TRect;
  lPoint: TPoint;
begin
  fForm.Visible := True;
  aNode.MakeVisible;
  lRect := aNode.DisplayRect(True);
  lPoint := fFrame.FolderTree.ClientToScreen(Point(lRect.Left + 2, lRect.Top + lRect.Height div 2));
  fFrame.FolderTree.Perform(WM_CONTEXTMENU, fFrame.FolderTree.Handle,
    MakeLParam(Word(lPoint.X), Word(lPoint.Y)));
end;

procedure TFolderTreeFrameTests.Popup_PointerCapturesActualNodeAndPreservesChecks;
begin
  fFrame.Initialize([Rule('X:\', True), Rule('Y:\', False)], []);
  fFrame.FolderTree.Selected := fFrame.FindNodeForTest('X:\');
  SendPointerContext(fFrame.FindNodeForTest('Y:\'));
  Assert.AreEqual(1, fPopupCount, 'Pointer context must open the native folder popup');
  Assert.AreEqual(1, fDiscoverCount);
  Assert.AreEqual('y:\', fDiscoveredPath, 'Context target differs from previous selection');
  Assert.AreEqual('x:\', fFrame.ContextPath, 'Popup target must not replace navigation identity');
  Assert.IsTrue(EvaluateFolderSelection('X:\', fFrame.Rules));
  Assert.IsFalse(EvaluateFolderSelection('Y:\', fFrame.Rules));
  Assert.AreEqual(2, Length(fFrame.Rules));
  Assert.AreEqual(0, fChangeCount);
end;

procedure TFolderTreeFrameTests.Popup_NativeCommandDiscoversCapturedNodeOnce(const aKeyboard: Boolean);
var
  lMessage: TMsg;
  lNativeCommandQueued: Boolean;
begin
  fFrame.Initialize([Rule('X:\', True), Rule('Y:\', False)], []);
  fNativePopupAction := True;
  fFrame.FolderTree.Selected := fFrame.FindNodeForTest('X:\');
  if aKeyboard then
  begin
    fFrame.FolderTree.Selected := fFrame.FindNodeForTest('Y:\');
    fPopupSelection := fFrame.FindNodeForTest('X:\');
    fForm.Visible := True;
    fFrame.FolderTree.Selected.MakeVisible;
    fFrame.FolderTree.Perform(WM_CONTEXTMENU, fFrame.FolderTree.Handle, -1);
  end else
    SendPointerContext(fFrame.FindNodeForTest('Y:\'));
  fPopupTimer.Enabled := False;
  Assert.AreEqual(1, fPopupCount, 'Native context menu must open');
  Assert.IsTrue(fPopupInitiallyEnabled, 'Native command must be available');
  Assert.IsTrue(fNativePopupKeysPosted, 'Keyboard messages must enter our popup owner queue');
  Assert.IsFalse(fNativePopupTimedOut, 'USER32 must select the menu item before the fixture deadline');
  lNativeCommandQueued := PeekMessage(lMessage, PopupList.Window, WM_COMMAND, WM_COMMAND, PM_NOREMOVE);
  if lNativeCommandQueued then
    lNativeCommandQueued := (LoWord(lMessage.wParam) = fFrame.DiscoverHereItem.Command) and
      (lMessage.lParam = 0);
  Assert.IsTrue(lNativeCommandQueued or (fDiscoverCount = 1),
    'USER32 must produce the selected command, queued or already dispatched');
  // TrackPopupMenu can return before VCL receives USER32's posted WM_COMMAND.
  Application.ProcessMessages;
  Assert.AreEqual(1, fDiscoverCount, 'Native menu selection must dispatch exactly one discovery');
  Assert.AreEqual('y:\', fDiscoveredPath, 'Queued command must retain the captured unchecked target');
  Assert.AreEqual('x:\', fFrame.ContextPath, 'Popup must preserve navigation identity');
  Assert.IsTrue(EvaluateFolderSelection('X:\', fFrame.Rules));
  Assert.IsFalse(EvaluateFolderSelection('Y:\', fFrame.Rules));
  Assert.AreEqual(2, Length(fFrame.Rules));
  Assert.AreEqual(0, fChangeCount);
  fFrame.DiscoverHereItem.Click;
  Application.ProcessMessages;
  Assert.AreEqual(1, fDiscoverCount, 'Completed dispatch must not leave a callable stale target');
end;
procedure TFolderTreeFrameTests.Popup_KeyboardFreezesSelectedNodeForItsLifetime;
begin
  fFrame.Initialize([Rule('X:\', True), Rule('Y:\', False)], []);
  fFrame.FolderTree.Selected := fFrame.FindNodeForTest('Y:\');
  fPopupSelection := fFrame.FindNodeForTest('X:\');
  fForm.Visible := True;
  fFrame.FolderTree.Selected.MakeVisible;
  // Windows dispatches the same (-1,-1) context position for Menu and Shift+F10.
  fFrame.FolderTree.Perform(WM_CONTEXTMENU, fFrame.FolderTree.Handle, -1);
  Assert.AreEqual(1, fPopupCount);
  Assert.AreEqual(1, fDiscoverCount);
  Assert.AreEqual('y:\', fDiscoveredPath, 'Menu invocation owns its captured path until close');
  Assert.AreEqual('x:\', fFrame.ContextPath);
  Assert.IsFalse(EvaluateFolderSelection('Y:\', fFrame.Rules));
  Assert.AreEqual(0, fChangeCount);
  fFrame.DiscoverHereItem.Click;
  Assert.AreEqual(1, fDiscoverCount, 'Closed menu must not retain a callable stale target');
end;

procedure TFolderTreeFrameTests.Popup_KeyboardLongPathUsesSelectedNode(const aScrolled: Boolean);
var
  lPath: string;
  lNode: TTreeNode;
  lRect: TRect;
  lPoint: TPoint;
begin
  lPath := 'Y:\' + StringOfChar('w', 120);
  fFrame.Initialize([Rule('X:\', True), Rule(lPath, False)], []);
  lNode := fFrame.FindNodeForTest(lPath);
  Assert.IsNotNull(lNode);
  fFrame.FolderTree.Selected := lNode;
  fPopupSelection := fFrame.FindNodeForTest('X:\');
  fForm.Visible := True;
  lNode.MakeVisible;
  fFrame.CancelEnumerationForTest;
  fFrame.FolderTree.Perform(WM_HSCROLL, SB_LEFT, 0);
  if aScrolled then
  begin
    fFrame.FolderTree.Perform(WM_HSCROLL, SB_LINERIGHT, 0);
    Assert.IsTrue(GetScrollPos(fFrame.FolderTree.Handle, SB_HORZ) > 0,
      'Scrolled case must move the native horizontal viewport');
  end;
  lRect := lNode.DisplayRect(True);
  lPoint := Point(lRect.Left + lRect.Width div 2, lRect.Top + lRect.Height div 2);
  Assert.IsFalse(PtInRect(fFrame.FolderTree.ClientRect, lPoint),
    'T054 fixture must reproduce the clipped text midpoint');
  // Exercise VCL native keyboard-context conversion, not a direct event-handler call.
  fFrame.FolderTree.Perform(WM_CONTEXTMENU, fFrame.FolderTree.Handle, -1);
  Assert.AreEqual(1, fPopupCount, 'A clipped label must not suppress the keyboard popup');
  Assert.AreEqual(1, fDiscoverCount);
  Assert.AreEqual(NormalizeSelectionPath(lPath), fDiscoveredPath);
  Assert.AreEqual('x:\', fFrame.ContextPath, 'Popup must retain target while selection changes');
  Assert.AreEqual(2, Length(fFrame.Rules));
  Assert.IsFalse(EvaluateFolderSelection(lPath, fFrame.Rules));
  Assert.AreEqual(0, fChangeCount);
end;

procedure TFolderTreeFrameTests.Popup_BlankSpaceCannotReusePriorTarget;
var
  lPoint: TPoint;
  lSelected: TTreeNode;
  i: Integer;
begin
  fFrame.Initialize([Rule('X:\', True)], []);
  fFrame.FolderTree.Selected := fFrame.FindNodeForTest('X:\');
  SendPointerContext(fFrame.FolderTree.Selected);
  Assert.AreEqual(1, fDiscoverCount);
  lSelected := fFrame.FolderTree.Selected;
  // Keep one real selected node so the blank region is independent of installed drive count.
  for i := fFrame.FolderTree.Items.Count - 1 downto 0 do
    if fFrame.FolderTree.Items[i] <> lSelected then
      fFrame.FolderTree.Items[i].Delete;
  lPoint := fFrame.FolderTree.ClientToScreen(Point(4, fFrame.FolderTree.ClientHeight - 2));
  fFrame.FolderTree.Perform(WM_CONTEXTMENU, fFrame.FolderTree.Handle,
    MakeLParam(Word(lPoint.X), Word(lPoint.Y)));
  Assert.AreEqual(1, fPopupCount, 'Blank area must not open an action for the selected node');
  fFrame.DiscoverHereItem.Click;
  Assert.AreEqual(1, fDiscoverCount);
  Assert.AreEqual(0, fChangeCount);
end;

procedure TFolderTreeFrameTests.Popup_DisabledAvailabilityBlocksUntilReenabled;
begin
  fFrame.Initialize([Rule('X:\', True)], []);
  fFrame.FolderTree.Selected := fFrame.FindNodeForTest('X:\');
  fPopupAvailabilityMode := 1;
  fFrame.DiscoveryEnabled := False;
  SendPointerContext(fFrame.FolderTree.Selected);
  Assert.AreEqual(1, fPopupCount);
  Assert.IsFalse(fPopupInitiallyEnabled, 'Busy discovery command must appear disabled');
  Assert.IsTrue(fPopupDisabledNativeState <> High(Cardinal), 'Native menu item must exist');
  Assert.IsTrue((fPopupDisabledNativeState and (MF_DISABLED or MF_GRAYED)) <> 0);
  Assert.AreEqual(0, fDiscoverCount);
  Assert.IsTrue(fFrame.FolderTree.Enabled, 'Busy discovery must leave folder navigation available');
  fFrame.DiscoveryEnabled := True;
  SendPointerContext(fFrame.FolderTree.Selected);
  Assert.AreEqual(2, fPopupCount);
  Assert.IsTrue(fPopupInitiallyEnabled, 'Command becomes available after the job ends');
  Assert.AreEqual(Cardinal(0), fPopupDisabledNativeState and (MF_DISABLED or MF_GRAYED));
  Assert.AreEqual(1, fDiscoverCount);
  Assert.AreEqual('x:\', fDiscoveredPath);
  Assert.IsTrue(EvaluateFolderSelection('X:\', fFrame.Rules));
  Assert.AreEqual(0, fChangeCount);
end;

procedure TFolderTreeFrameTests.Popup_AvailabilityChangesUpdateOpenMenuAndGuardDispatch;
begin
  fFrame.Initialize([Rule('X:\', True), Rule('Y:\', False)], []);
  fFrame.FolderTree.Selected := fFrame.FindNodeForTest('X:\');
  fPopupAvailabilityMode := 2;
  SendPointerContext(fFrame.FindNodeForTest('Y:\'));
  Assert.AreEqual(1, fPopupCount);
  Assert.IsTrue(fPopupInitiallyEnabled);
  Assert.IsTrue(fPopupDisabledNativeState <> High(Cardinal), 'Open native menu item must exist');
  Assert.IsTrue((fPopupDisabledNativeState and (MF_DISABLED or MF_GRAYED)) <> 0,
    'Changing availability must disable the already open native menu item');
  Assert.AreEqual(0, fPopupRejectedCount, 'A command already dispatched must recheck availability');
  Assert.IsTrue(fPopupEnabledNativeState <> High(Cardinal));
  Assert.AreEqual(Cardinal(0), fPopupEnabledNativeState and (MF_DISABLED or MF_GRAYED));
  Assert.AreEqual(1, fDiscoverCount);
  Assert.AreEqual('y:\', fDiscoveredPath, 'Availability changes preserve the popup target');
  Assert.AreEqual('x:\', fFrame.ContextPath);
  Assert.IsFalse(EvaluateFolderSelection('Y:\', fFrame.Rules));
  Assert.AreEqual(0, fChangeCount);
end;

initialization
  TDUnitX.RegisterTestFixture(TFolderTreeFrameTests);

end.
