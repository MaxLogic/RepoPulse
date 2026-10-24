unit UFolderTreeFrame;

interface

uses
  System.Classes, System.Generics.Collections, System.SyncObjs, System.SysUtils, System.Types,
  Vcl.ComCtrls, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.Menus, Vcl.StdCtrls,
  UFolderSelection;

const
  cFolderEnumerationQueueCapacity = 32;

type
  TFolderDiscoverHereEvent = procedure(aSender: TObject; const aPath: string) of object;

  TFolderEnumerationResult = record
    ParentPath, ChildPath: string;
    Reparse, Complete: Boolean;
    ErrorCode: Cardinal;
  end;

  TFolderEnumerationWorker = class(TThread)
  private
    fRequests: TThreadedQueue<string>;
    fResults: TThreadedQueue<TFolderEnumerationResult>;
    function Deliver(const aResult: TFolderEnumerationResult): Boolean;
    procedure Enumerate(const aPath: string);
  protected
    procedure Execute; override;
  public
    constructor Create(const aRequests: TThreadedQueue<string>;
      const aResults: TThreadedQueue<TFolderEnumerationResult>);
  end;

  TFolderTreeFrame = class(TFrame)
    FolderTree: TTreeView;
    HeadingText: TStaticText;
    StatusText: TStaticText;
    DeliveryTimer: TTimer;
    FolderPopup: TPopupMenu;
    DiscoverHereItem: TMenuItem;
    procedure FolderTreeContextPopup(aSender: TObject; aMousePos: TPoint; var aHandled: Boolean);
    procedure DiscoverHereItemClick(aSender: TObject);
    procedure FolderTreeCheckStateChanged(aSender: TCustomTreeView; aNode: TTreeNode;
      aCheckState: TNodeCheckState);
    procedure FolderTreeKeyDown(aSender: TObject; var aKey: Word; aShift: TShiftState);
    procedure FolderTreeExpanding(aSender: TObject; aNode: TTreeNode; var aAllowExpansion: Boolean);
    procedure FolderTreeExpanded(aSender: TObject; aNode: TTreeNode);
    procedure FolderTreeCollapsed(aSender: TObject; aNode: TTreeNode);
    procedure FolderTreeDeletion(aSender: TObject; aNode: TTreeNode);
    procedure DeliveryTimerTimer(aSender: TObject);
  private
    fOnSelectionChanged: TNotifyEvent;
    fOnDiscoverHere: TFolderDiscoverHereEvent;
    fDiscoveryEnabled: Boolean;
    fPopupPath: string;
    fRules: TArray<TFolderSelectionRule>;
    fRestorePaths: TArray<string>;
    fRestoreIndex: Integer;
    fExpanded: TDictionary<string, Boolean>;
    fNodes: TDictionary<string, TTreeNode>;
    fNodeData: TObjectDictionary<string, TObject>;
    fPending: TDictionary<string, Boolean>;
    fRequests: TThreadedQueue<string>;
    fResults: TThreadedQueue<TFolderEnumerationResult>;
    fWorker: TFolderEnumerationWorker;
    fUpdating: Boolean;
    procedure SetDiscoveryEnabled(const aValue: Boolean);
    function EnsureNode(const aPath: string): TTreeNode;
    procedure RefreshChecks;
    procedure ApplySelection(const aNode: TTreeNode; const aIncluded: Boolean);
    procedure StartWorker;
  protected
    function GetRules: TArray<TFolderSelectionRule>;
    function GetExpandedPaths: TArray<string>;
    function GetContextPath: string;
    function GetEnumerationBusy: Boolean;
    function GetPendingEnumerationCount: Integer;
    function FindNode(const aPath: string): TTreeNode;
    function NodePath(const aNode: TTreeNode): string;
    procedure RequestChildren(const aPath: string);
    procedure CancelEnumeration;
  public
    constructor Create(aOwner: TComponent); override;
    destructor Destroy; override;
    procedure Initialize(const aRules: TArray<TFolderSelectionRule>;
      const aExpandedPaths: TArray<string>);
    property Rules: TArray<TFolderSelectionRule> read GetRules;
    property ExpandedPaths: TArray<string> read GetExpandedPaths;
    property ContextPath: string read GetContextPath;
    property DiscoveryEnabled: Boolean read fDiscoveryEnabled write SetDiscoveryEnabled;
    property OnDiscoverHere: TFolderDiscoverHereEvent read fOnDiscoverHere write fOnDiscoverHere;
    property OnSelectionChanged: TNotifyEvent read fOnSelectionChanged write fOnSelectionChanged;
  end;

implementation

uses
  System.IOUtils,
  Winapi.Messages, Winapi.Windows;

{$R *.dfm}

type
  TFolderTreeView = class(TTreeView)
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure WMContextMenu(var aMessage: TWMContextMenu); message WM_CONTEXTMENU;
  end;

  TFolderNodeData = class
    Path: string;
    Loaded, Reparse: Boolean;
  end;

resourcestring
  rsLoadingFolders = 'Loading folders: %s';
  rsFoldersUnavailable = 'Folder unavailable: %s (%s)';
  rsFoldersLoaded = 'Folders loaded: %s';
  rsFolderQueueFull = 'Folder queue full. Collapse and expand the folder to retry.';
  rsFolderChecked = 'checked';
  rsFolderUnchecked = 'unchecked';
  rsFolderMixed = 'mixed';

procedure TFolderTreeView.WMContextMenu(var aMessage: TWMContextMenu);
var
  lHandled: Boolean;
begin
  if (aMessage.Result = 0) and not (csDesigning in ComponentState) and
    (aMessage.Pos.X = -1) and (aMessage.Pos.Y = -1) then
  begin
    SetFocus;
    lHandled := False;
    // T-054: preserve keyboard context before VCL substitutes a clipped label midpoint.
    DoContextPopup(Point(-1, -1), lHandled);
    aMessage.Result := Ord(lHandled);
    if lHandled then
    begin
      if not (csDestroying in ComponentState) then
        MouseUp(mbRight, KeyboardStateToShiftState, -1, -1);
      Exit;
    end;
  end;
  inherited;
end;

procedure TFolderTreeView.CreateWnd;
var
  lFrame: TFolderTreeFrame;
  lNode: TTreeNode;
  lUpdating: Boolean;
begin
  if not (Owner is TFolderTreeFrame) or
    not Assigned(TFolderTreeFrame(Owner).fNodes) then
  begin
    inherited;
    Exit;
  end;
  lFrame := TFolderTreeFrame(Owner);
  lUpdating := lFrame.fUpdating;
  lFrame.fUpdating := True;
  try
    inherited;
    // T-050: VCL restores new node objects while retaining their Data pointers.
    lFrame.fNodes.Clear;
    for lNode in Items do
      if Assigned(lNode.Data) then
        lFrame.fNodes.Add(lFrame.NodePath(lNode), lNode);
    lFrame.RefreshChecks;
  finally
    lFrame.fUpdating := lUpdating;
  end;
end;

procedure TFolderTreeView.DestroyWnd;
var
  lFrame: TFolderTreeFrame;
  lUpdating: Boolean;
begin
  if not (Owner is TFolderTreeFrame) or
    not Assigned(TFolderTreeFrame(Owner).fNodes) then
  begin
    inherited;
    Exit;
  end;
  lFrame := TFolderTreeFrame(Owner);
  lUpdating := lFrame.fUpdating;
  lFrame.fUpdating := True;
  try
    inherited;
  finally
    // A hidden parent can defer CreateWnd; never retain freed native nodes.
    lFrame.fNodes.Clear;
    lFrame.fUpdating := lUpdating;
  end;
end;

procedure TFolderTreeFrame.SetDiscoveryEnabled(const aValue: Boolean);
begin
  fDiscoveryEnabled := aValue;
  DiscoverHereItem.Enabled := fDiscoveryEnabled and (fPopupPath <> '') and Assigned(fOnDiscoverHere);
end;

procedure TFolderTreeFrame.FolderTreeContextPopup(aSender: TObject; aMousePos: TPoint;
  var aHandled: Boolean);
var
  lNode: TTreeNode;
  lPoint: TPoint;
  lRect: TRect;
  lMessage: TMsg;
begin
  aHandled := True;
  fPopupPath := '';
  DiscoverHereItem.Enabled := False;
  if (aMousePos.X = -1) and (aMousePos.Y = -1) then
  begin
    lNode := FolderTree.Selected;
    if not Assigned(lNode) then
      Exit;
    lRect := lNode.DisplayRect(True);
    lPoint := FolderTree.ClientToScreen(Point(lRect.Left, lRect.Bottom));
  end else begin
    lNode := FolderTree.GetNodeAt(aMousePos.X, aMousePos.Y);
    lPoint := FolderTree.ClientToScreen(aMousePos);
  end;
  if not Assigned(lNode) then
    Exit;
  fPopupPath := NodePath(lNode);
  DiscoverHereItem.Enabled := fDiscoveryEnabled and (fPopupPath <> '') and Assigned(fOnDiscoverHere);
  FolderPopup.PopupComponent := FolderTree;
  try
    FolderPopup.Popup(lPoint.X, lPoint.Y);
    // USER32 can leave the selected command queued when TrackPopupMenu returns. Dispatch
    // only this popup action while its captured path and availability are valid.
    if PeekMessage(lMessage, PopupList.Window, WM_COMMAND, WM_COMMAND, PM_NOREMOVE) and
      (lMessage.wParam = DiscoverHereItem.Command) and (lMessage.lParam = 0) then
      if PeekMessage(lMessage, PopupList.Window, WM_COMMAND, WM_COMMAND, PM_REMOVE) then
        DispatchMessage(lMessage);
  finally
    fPopupPath := '';
    DiscoverHereItem.Enabled := False;
  end;
end;

procedure TFolderTreeFrame.DiscoverHereItemClick(aSender: TObject);
var
  lPath: string;
begin
  lPath := fPopupPath;
  if fDiscoveryEnabled and (lPath <> '') and Assigned(fOnDiscoverHere) then
    fOnDiscoverHere(Self, lPath);
end;

constructor TFolderEnumerationWorker.Create(const aRequests: TThreadedQueue<string>;
  const aResults: TThreadedQueue<TFolderEnumerationResult>);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fRequests := aRequests;
  fResults := aResults;
end;

function TFolderEnumerationWorker.Deliver(const aResult: TFolderEnumerationResult): Boolean;
begin
  Result := False;
  while not Terminated do
    if fResults.PushItem(aResult) = TWaitResult.wrSignaled then
      Exit(True);
end;

procedure TFolderEnumerationWorker.Enumerate(const aPath: string);
var
  lResult: TFolderEnumerationResult;
  lData: TWin32FindData;
  lHandle: THandle;
  lAttributes, lError: Cardinal;
  lName: string;
begin
  lResult := Default(TFolderEnumerationResult);
  lResult.ParentPath := aPath;
  lAttributes := GetFileAttributes(PChar(aPath));
  if lAttributes = INVALID_FILE_ATTRIBUTES then
    lResult.ErrorCode := GetLastError
  else if (lAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
    lResult.Reparse := True
  else if not Terminated then
  begin
    lHandle := FindFirstFile(PChar(IncludeTrailingPathDelimiter(aPath) + '*'), lData);
    if lHandle = INVALID_HANDLE_VALUE then
    begin
      lError := GetLastError;
      if lError <> ERROR_FILE_NOT_FOUND then
        lResult.ErrorCode := lError;
    end else begin
      try
        repeat
          if Terminated then
            Exit;
          lName := string(lData.cFileName);
          if ((lData.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) and
            (lName <> '.') and (lName <> '..') then
          begin
            lResult.ChildPath := IncludeTrailingPathDelimiter(aPath) + lName;
            lResult.Reparse := (lData.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0;
            if not Deliver(lResult) then
              Exit;
          end;
          if Terminated then
            Exit;
          if not FindNextFile(lHandle, lData) then
          begin
            lError := GetLastError;
            if lError <> ERROR_NO_MORE_FILES then
              lResult.ErrorCode := lError;
            Break;
          end;
        until False;
      finally
        Winapi.Windows.FindClose(lHandle);
      end;
      lResult.Reparse := False;
    end;
  end;
  lResult.ChildPath := '';
  lResult.Complete := True;
  Deliver(lResult);
end;

procedure TFolderEnumerationWorker.Execute;
var
  lPath: string;
  lResult: TFolderEnumerationResult;
begin
  while not Terminated do
    if fRequests.PopItem(lPath) = TWaitResult.wrSignaled then
    begin
      try
        if not Terminated then
          Enumerate(lPath);
      except
        on E: Exception do
        begin
          // T-040: preserve a terminal failure so the UI never leaves this path pending.
          lResult := Default(TFolderEnumerationResult);
          lResult.ParentPath := lPath;
          lResult.Complete := True;
          lResult.ErrorCode := ERROR_GEN_FAILURE;
          Deliver(lResult);
        end;
      end;
    end;
end;

constructor TFolderTreeFrame.Create(aOwner: TComponent);
begin
  inherited;
  fDiscoveryEnabled := True;
  fExpanded := TDictionary<string, Boolean>.Create;
  fNodes := TDictionary<string, TTreeNode>.Create;
  fNodeData := TObjectDictionary<string, TObject>.Create([doOwnsValues]);
  fPending := TDictionary<string, Boolean>.Create;
end;

destructor TFolderTreeFrame.Destroy;
begin
  CancelEnumeration;
  if Assigned(FolderTree) then
    FolderTree.Items.Clear;
  fPending.Free;
  FreeAndNil(fNodes);
  fNodeData.Free;
  fExpanded.Free;
  inherited;
end;

procedure TFolderTreeFrame.StartWorker;
begin
  if Assigned(fWorker) then
    Exit;
  fRequests := TThreadedQueue<string>.Create(cFolderEnumerationQueueCapacity, 0, 50);
  fResults := TThreadedQueue<TFolderEnumerationResult>.Create(128, 20, 0);
  fWorker := TFolderEnumerationWorker.Create(fRequests, fResults);
  fWorker.Start;
end;

procedure TFolderTreeFrame.CancelEnumeration;
begin
  if Assigned(DeliveryTimer) then
    DeliveryTimer.Enabled := False;
  if Assigned(fWorker) then
  begin
    fWorker.Terminate;
    fRequests.DoShutDown;
    fResults.DoShutDown;
    repeat
      // Repeated cancellation closes the race between the stop check and a blocking OS call.
      CancelSynchronousIo(fWorker.Handle);
    until WaitForSingleObject(fWorker.Handle, 50) = WAIT_OBJECT_0;
    fWorker.WaitFor;
    FreeAndNil(fWorker);
  end;
  FreeAndNil(fRequests);
  FreeAndNil(fResults);
  if Assigned(fPending) then
    fPending.Clear;
  fRestorePaths := nil;
  fRestoreIndex := 0;
end;

procedure TFolderTreeFrame.Initialize(const aRules: TArray<TFolderSelectionRule>;
  const aExpandedPaths: TArray<string>);
var
  lRule: TFolderSelectionRule;
  lPath: string;
  lNode: TTreeNode;
  lDrives: Cardinal;
  i: Integer;
begin
  CancelEnumeration;
  FolderTree.HandleNeeded;
  fUpdating := True;
  FolderTree.Items.BeginUpdate;
  try
    FolderTree.Items.Clear;
    fExpanded.Clear;
    fRules := Copy(aRules);
    lDrives := GetLogicalDrives;
    for i := 0 to 25 do
      if (lDrives and (Cardinal(1) shl i)) <> 0 then
        EnsureNode(Char(Ord('a') + i) + ':\');
    for lRule in fRules do
      EnsureNode(lRule.Path);
    for lPath in aExpandedPaths do
    begin
      lNode := EnsureNode(lPath);
      if Assigned(lNode) then
      begin
        fExpanded.AddOrSetValue(NodePath(lNode), True);
        lNode.Expand(False);
      end;
    end;
    RefreshChecks;
  finally
    FolderTree.Items.EndUpdate;
    fUpdating := False;
  end;
  fRestorePaths := Copy(aExpandedPaths);
  fRestoreIndex := 0;
  DeliveryTimer.Enabled := Length(fRestorePaths) > 0;
end;

function TFolderTreeFrame.EnsureNode(const aPath: string): TTreeNode;
var
  lPath, lRoot, lParentPath: string;
  lParent: TTreeNode;
  lData: TFolderNodeData;
begin
  FolderTree.HandleNeeded;
  lPath := NormalizeSelectionPath(aPath);
  if lPath = '' then
    Exit(nil);
  if fNodes.TryGetValue(lPath, Result) then
    Exit;
  lRoot := NormalizeSelectionPath(TPath.GetPathRoot(lPath));
  lParent := nil;
  if lPath <> lRoot then
  begin
    lParentPath := ExtractFileDir(lPath);
    if (lParentPath <> '') and (lParentPath <> lPath) then
      lParent := EnsureNode(lParentPath);
  end;
  lData := TFolderNodeData.Create;
  lData.Path := lPath;
  try
    Result := FolderTree.Items.AddChildObject(lParent, lPath, lData);
  except
    lData.Free;
    raise;
  end;
  fNodeData.Add(lPath, lData);
  fNodes.Add(lPath, Result);
  Result.HasChildren := True;
end;

function TFolderTreeFrame.FindNode(const aPath: string): TTreeNode;
begin
  if not fNodes.TryGetValue(NormalizeSelectionPath(aPath), Result) then
    Result := nil;
end;

function TFolderTreeFrame.NodePath(const aNode: TTreeNode): string;
begin
  Result := '';
  if Assigned(aNode) and Assigned(aNode.Data) then
    Result := TFolderNodeData(aNode.Data).Path;
end;

procedure TFolderTreeFrame.RefreshChecks;
var
  lNode: TTreeNode;
  lState: TFolderSelectionState;
  lText: string;
  lUpdating: Boolean;
begin
  lUpdating := fUpdating;
  fUpdating := True;
  try
    for lNode in fNodes.Values do
    begin
      lState := GetFolderSelectionState(NodePath(lNode), fRules);
      case lState of
        TFolderSelectionState.fssChecked:
          begin
            lNode.CheckState := TNodeCheckState.ncsChecked;
            lText := rsFolderChecked;
          end;
        TFolderSelectionState.fssMixed:
          begin
            lNode.CheckState := TNodeCheckState.ncsPartial;
            lText := rsFolderMixed;
          end;
      else
        lNode.CheckState := TNodeCheckState.ncsUnchecked;
        lText := rsFolderUnchecked;
      end;
      // Native check-state exposure still requires T-044 live proof; text preserves meaning.
      lNode.Text := NodePath(lNode) + ' (' + lText + ')';
    end;
  finally
    fUpdating := lUpdating;
  end;
end;

procedure TFolderTreeFrame.ApplySelection(const aNode: TTreeNode; const aIncluded: Boolean);
begin
  if fUpdating or not Assigned(aNode) then
    Exit;
  fRules := SetFolderSelection(NodePath(aNode), aIncluded, fRules);
  RefreshChecks;
  if Assigned(fOnSelectionChanged) then
    fOnSelectionChanged(Self);
end;

procedure TFolderTreeFrame.FolderTreeCheckStateChanged(aSender: TCustomTreeView;
  aNode: TTreeNode; aCheckState: TNodeCheckState);
begin
  ApplySelection(aNode, aCheckState <> TNodeCheckState.ncsUnchecked);
end;

procedure TFolderTreeFrame.FolderTreeKeyDown(aSender: TObject; var aKey: Word; aShift: TShiftState);
begin
  if aKey = VK_SPACE then
  begin
    aKey := 0;
    if Assigned(FolderTree.Selected) then
      ApplySelection(FolderTree.Selected,
        GetFolderSelectionState(NodePath(FolderTree.Selected), fRules) <> TFolderSelectionState.fssChecked);
  end;
end;

procedure TFolderTreeFrame.FolderTreeExpanding(aSender: TObject; aNode: TTreeNode;
  var aAllowExpansion: Boolean);
begin
  if not fUpdating then
    RequestChildren(NodePath(aNode));
end;

procedure TFolderTreeFrame.FolderTreeExpanded(aSender: TObject; aNode: TTreeNode);
begin
  if not fUpdating then
    fExpanded.AddOrSetValue(NodePath(aNode), True);
end;

procedure TFolderTreeFrame.FolderTreeCollapsed(aSender: TObject; aNode: TTreeNode);
begin
  if not fUpdating then
    fExpanded.Remove(NodePath(aNode));
end;

procedure TFolderTreeFrame.FolderTreeDeletion(aSender: TObject; aNode: TTreeNode);
begin
  if Assigned(aNode.Data) then
  begin
    if Assigned(fNodes) then
      fNodes.Remove(NodePath(aNode));
    fNodeData.Remove(NodePath(aNode));
    aNode.Data := nil;
  end;
end;

procedure TFolderTreeFrame.RequestChildren(const aPath: string);
var
  lNode: TTreeNode;
  lPath: string;
  lData: TFolderNodeData;
begin
  lNode := FindNode(aPath);
  if not Assigned(lNode) then
    Exit;
  lData := TFolderNodeData(lNode.Data);
  if lData.Loaded or lData.Reparse then
    Exit;
  lPath := lData.Path;
  if fPending.ContainsKey(lPath) then
    Exit;
  if fPending.Count >= cFolderEnumerationQueueCapacity then
  begin
    StatusText.Caption := rsFolderQueueFull;
    Exit;
  end;
  StartWorker;
  if fRequests.PushItem(lPath) = TWaitResult.wrSignaled then
  begin
    fPending.Add(lPath, True);
    StatusText.Caption := Format(rsLoadingFolders, [lPath]);
    DeliveryTimer.Enabled := True;
  end;
end;

procedure TFolderTreeFrame.DeliveryTimerTimer(aSender: TObject);
var
  lResult: TFolderEnumerationResult;
  lNode: TTreeNode;
  lData: TFolderNodeData;
  i: Integer;
begin
  FolderTree.HandleNeeded;
  while (fRestoreIndex < Length(fRestorePaths)) and
    (fPending.Count < cFolderEnumerationQueueCapacity) do
  begin
    RequestChildren(fRestorePaths[fRestoreIndex]);
    Inc(fRestoreIndex);
  end;
  if not Assigned(fResults) then
  begin
    DeliveryTimer.Enabled := GetEnumerationBusy;
    Exit;
  end;
  fUpdating := True;
  FolderTree.Items.BeginUpdate;
  try
    for i := 1 to 64 do
    begin
      if fResults.PopItem(lResult) <> TWaitResult.wrSignaled then
        Break;
      if not fPending.ContainsKey(lResult.ParentPath) then
        Continue;
      if lResult.Complete then
      begin
        lNode := FindNode(lResult.ParentPath);
        if Assigned(lNode) then
        begin
          lData := TFolderNodeData(lNode.Data);
          lData.Loaded := lResult.ErrorCode = 0;
          lData.Reparse := lResult.Reparse;
          if lData.Loaded then
          begin
            lNode.HasChildren := lNode.Count > 0;
            if fExpanded.ContainsKey(lData.Path) then
              lNode.Expand(False);
          end;
        end;
        fPending.Remove(lResult.ParentPath);
        if lResult.ErrorCode <> 0 then
          StatusText.Caption := Format(rsFoldersUnavailable,
            [lResult.ParentPath, SysErrorMessage(lResult.ErrorCode)])
        else
          StatusText.Caption := Format(rsFoldersLoaded, [lResult.ParentPath]);
      end else begin
        lNode := EnsureNode(lResult.ChildPath);
        lData := TFolderNodeData(lNode.Data);
        lData.Reparse := lResult.Reparse;
        if lData.Reparse then
          lNode.HasChildren := lNode.Count > 0;
      end;
    end;
    RefreshChecks;
  finally
    FolderTree.Items.EndUpdate;
    fUpdating := False;
  end;
  DeliveryTimer.Enabled := GetEnumerationBusy;
end;

function TFolderTreeFrame.GetRules: TArray<TFolderSelectionRule>;
begin
  Result := Copy(fRules);
end;

function TFolderTreeFrame.GetExpandedPaths: TArray<string>;
begin
  Result := fExpanded.Keys.ToArray;
end;

function TFolderTreeFrame.GetContextPath: string;
begin
  Result := NodePath(FolderTree.Selected);
end;

function TFolderTreeFrame.GetEnumerationBusy: Boolean;
begin
  Result := (fPending.Count <> 0) or (fRestoreIndex < Length(fRestorePaths));
end;

function TFolderTreeFrame.GetPendingEnumerationCount: Integer;
begin
  Result := fPending.Count;
end;

initialization
  System.Classes.RegisterClass(TFolderTreeView);

finalization
  System.Classes.UnRegisterClass(TFolderTreeView);

end.
