unit URepositoryAccessibility;

interface

uses
  VirtualTrees;

procedure InstallRepositoryAccessibility(const aTree: TVirtualStringTree);

implementation

uses
  System.Classes, System.Types, System.Variants,
  Winapi.ActiveX, Winapi.OleAcc, Winapi.Windows,
  VirtualTrees.Types;

type
  TRepositoryTreeLifetime = class(TComponent)
  private
    fTree: TVirtualStringTree;
  protected
    procedure Notification(aComponent: TComponent; aOperation: TOperation); override;
  public
    constructor CreateForTree(const aTree: TVirtualStringTree);
    destructor Destroy; override;
    property Tree: TVirtualStringTree read fTree;
  end;

  // Simple child IDs address the current flat projection, without per-row COM objects.
  TRepositoryTreeAccessibility = class(TInterfacedObject, IDispatch, IAccessible)
  private
    fLifetime: TRepositoryTreeLifetime;
    function ResolveChild(const aChild: OleVariant; out aNode: PVirtualNode): HResult;
  public
    constructor Create(const aTree: TVirtualStringTree);
    destructor Destroy; override;
    function Get_accParent(out aParent: IDispatch): HResult; stdcall;
    function Get_accChildCount(out aCount: Integer): HResult; stdcall;
    function Get_accChild(aChild: OleVariant; out aDispatch: IDispatch): HResult; stdcall;
    function Get_accName(aChild: OleVariant; out aName: WideString): HResult; stdcall;
    function Get_accValue(aChild: OleVariant; out aValue: WideString): HResult; stdcall;
    function Get_accDescription(aChild: OleVariant; out aDescription: WideString): HResult; stdcall;
    function Get_accRole(aChild: OleVariant; out aRole: OleVariant): HResult; stdcall;
    function Get_accState(aChild: OleVariant; out aState: OleVariant): HResult; stdcall;
    function Get_accHelp(aChild: OleVariant; out aHelp: WideString): HResult; stdcall;
    function Get_accHelpTopic(out aFileName: WideString; aChild: OleVariant;
      out aTopic: Integer): HResult; stdcall;
    function Get_accKeyboardShortcut(aChild: OleVariant; out aShortcut: WideString): HResult; stdcall;
    function Get_accFocus(out aChild: OleVariant): HResult; stdcall;
    function Get_accSelection(out aChildren: OleVariant): HResult; stdcall;
    function Get_accDefaultAction(aChild: OleVariant; out aAction: WideString): HResult; stdcall;
    function accSelect(aFlags: Integer; aChild: OleVariant): HResult; stdcall;
    function accLocation(out aLeft, aTop, aWidth, aHeight: Integer;
      aChild: OleVariant): HResult; stdcall;
    function accNavigate(aDirection: Integer; aStart: OleVariant;
      out aEnd: OleVariant): HResult; stdcall;
    function accHitTest(aLeft, aTop: Integer; out aChild: OleVariant): HResult; stdcall;
    function accDoDefaultAction(aChild: OleVariant): HResult; stdcall;
    function Set_accName(aChild: OleVariant; const aName: WideString): HResult; stdcall;
    function Set_accValue(aChild: OleVariant; const aValue: WideString): HResult; stdcall;
    function GetIDsOfNames(const aIid: TGUID; aNames: Pointer; aCount, aLocale: Integer;
      aDispIds: Pointer): HResult; stdcall;
    function GetTypeInfo(aIndex, aLocale: Integer; out aTypeInfo): HResult; stdcall;
    function GetTypeInfoCount(out aCount: Integer): HResult; stdcall;
    function Invoke(aDispId: Integer; const aIid: TGUID; aLocale: Integer;
      aFlags: Word; var aParams; aResult, aException, aArgError: Pointer): HResult; stdcall;
  end;

constructor TRepositoryTreeLifetime.CreateForTree(const aTree: TVirtualStringTree);
begin
  inherited Create(nil);
  fTree := aTree;
  fTree.FreeNotification(Self);
end;

destructor TRepositoryTreeLifetime.Destroy;
begin
  if fTree <> nil then
    fTree.RemoveFreeNotification(Self);
  inherited;
end;

procedure TRepositoryTreeLifetime.Notification(aComponent: TComponent;
  aOperation: TOperation);
begin
  inherited;
  if (aOperation = opRemove) and (aComponent = fTree) then
    fTree := nil;
end;

constructor TRepositoryTreeAccessibility.Create(const aTree: TVirtualStringTree);
begin
  inherited Create;
  fLifetime := TRepositoryTreeLifetime.CreateForTree(aTree);
end;

destructor TRepositoryTreeAccessibility.Destroy;
begin
  fLifetime.Free;
  inherited;
end;

function TRepositoryTreeAccessibility.ResolveChild(const aChild: OleVariant;
  out aNode: PVirtualNode): HResult;
var
  lIndex: Integer;
  lTop: TDimension;
begin
  aNode := nil;
  Result := E_INVALIDARG;
  if (fLifetime.Tree = nil) or (VarType(aChild) <> varInteger) then
    Exit;
  lIndex := aChild;
  if (lIndex < 0) or (Cardinal(lIndex) > fLifetime.Tree.RootNodeCount) then
    Exit;
  if lIndex > 0 then
  begin
    // Repository rows are a flat list with one uniform, DPI-scaled node height.
    aNode := fLifetime.Tree.GetNodeAt(0,
      (lIndex - 1) * fLifetime.Tree.DefaultNodeHeight, False, lTop);
    if (aNode = nil) or (aNode.Index <> Cardinal(lIndex - 1)) then
      Exit;
  end;
  Result := S_OK;
end;

function TRepositoryTreeAccessibility.Get_accParent(out aParent: IDispatch): HResult;
var
  lParent: IAccessible;
begin
  aParent := nil;
  Result := S_FALSE;
  if (fLifetime.Tree <> nil) and fLifetime.Tree.HandleAllocated then
  begin
    Result := AccessibleObjectFromWindow(fLifetime.Tree.Handle, OBJID_WINDOW,
      IID_IAccessible, lParent);
    if Result = S_OK then
      aParent := lParent;
  end;
end;

function TRepositoryTreeAccessibility.Get_accChildCount(out aCount: Integer): HResult;
begin
  aCount := 0;
  Result := E_INVALIDARG;
  if fLifetime.Tree = nil then
    Exit;
  aCount := fLifetime.Tree.RootNodeCount;
  Result := S_OK;
end;

function TRepositoryTreeAccessibility.Get_accChild(aChild: OleVariant;
  out aDispatch: IDispatch): HResult;
var
  lNode: PVirtualNode;
begin
  aDispatch := nil;
  Result := ResolveChild(aChild, lNode);
  if Result = S_OK then
    Result := S_FALSE;
end;

function TRepositoryTreeAccessibility.Get_accName(aChild: OleVariant;
  out aName: WideString): HResult;
var
  lNode: PVirtualNode;
begin
  aName := '';
  Result := ResolveChild(aChild, lNode);
  if Result <> S_OK then
    Exit;
  if lNode = nil then
    aName := fLifetime.Tree.AccessibleName
  else
    aName := fLifetime.Tree.Text[lNode, fLifetime.Tree.Header.MainColumn];
end;

function TRepositoryTreeAccessibility.Get_accValue(aChild: OleVariant;
  out aValue: WideString): HResult;
var
  lNode: PVirtualNode;
begin
  aValue := '';
  Result := ResolveChild(aChild, lNode);
  if Result = S_OK then
    Result := S_FALSE;
end;

function TRepositoryTreeAccessibility.Get_accDescription(aChild: OleVariant;
  out aDescription: WideString): HResult;
begin
  Result := Get_accValue(aChild, aDescription);
end;

function TRepositoryTreeAccessibility.Get_accRole(aChild: OleVariant;
  out aRole: OleVariant): HResult;
var
  lNode: PVirtualNode;
begin
  aRole := Unassigned;
  Result := ResolveChild(aChild, lNode);
  if Result <> S_OK then
    Exit;
  if lNode = nil then
    aRole := ROLE_SYSTEM_OUTLINE
  else
    aRole := ROLE_SYSTEM_OUTLINEITEM;
end;

function TRepositoryTreeAccessibility.Get_accState(aChild: OleVariant;
  out aState: OleVariant): HResult;
var
  lNode: PVirtualNode;
  lFlags: Integer;
  lRect, lIntersection: TRect;
begin
  aState := Unassigned;
  Result := ResolveChild(aChild, lNode);
  if Result <> S_OK then
    Exit;
  lFlags := STATE_SYSTEM_FOCUSABLE;
  if not fLifetime.Tree.Enabled then
    lFlags := lFlags or STATE_SYSTEM_UNAVAILABLE;
  if not fLifetime.Tree.Visible then
    lFlags := lFlags or STATE_SYSTEM_INVISIBLE;
  if lNode <> nil then
  begin
    lFlags := lFlags or STATE_SYSTEM_SELECTABLE;
    if fLifetime.Tree.Selected[lNode] then
      lFlags := lFlags or STATE_SYSTEM_SELECTED;
    if fLifetime.Tree.Focused and (fLifetime.Tree.FocusedNode = lNode) then
      lFlags := lFlags or STATE_SYSTEM_FOCUSED;
    lRect := fLifetime.Tree.GetDisplayRect(lNode, NoColumn, False);
    if not IntersectRect(lIntersection, lRect, fLifetime.Tree.ClientRect) then
      lFlags := lFlags or STATE_SYSTEM_OFFSCREEN;
  end else if fLifetime.Tree.Focused then
    lFlags := lFlags or STATE_SYSTEM_FOCUSED;
  aState := lFlags;
end;

function TRepositoryTreeAccessibility.Get_accHelp(aChild: OleVariant;
  out aHelp: WideString): HResult;
begin
  Result := Get_accValue(aChild, aHelp);
end;

function TRepositoryTreeAccessibility.Get_accHelpTopic(out aFileName: WideString;
  aChild: OleVariant; out aTopic: Integer): HResult;
begin
  aTopic := 0;
  Result := Get_accValue(aChild, aFileName);
end;

function TRepositoryTreeAccessibility.Get_accKeyboardShortcut(aChild: OleVariant;
  out aShortcut: WideString): HResult;
begin
  Result := Get_accValue(aChild, aShortcut);
end;

function TRepositoryTreeAccessibility.Get_accFocus(out aChild: OleVariant): HResult;
begin
  aChild := Unassigned;
  Result := E_INVALIDARG;
  if fLifetime.Tree = nil then
    Exit;
  if fLifetime.Tree.Focused then
  begin
    aChild := CHILDID_SELF;
    if fLifetime.Tree.FocusedNode <> nil then
      aChild := Integer(fLifetime.Tree.FocusedNode.Index + 1);
  end;
  Result := S_OK;
end;

function TRepositoryTreeAccessibility.Get_accSelection(out aChildren: OleVariant): HResult;
var
  lNode: PVirtualNode;
begin
  aChildren := Unassigned;
  Result := E_INVALIDARG;
  if fLifetime.Tree = nil then
    Exit;
  Result := S_FALSE;
  lNode := fLifetime.Tree.GetFirstSelected;
  if lNode <> nil then
  begin
    aChildren := Integer(lNode.Index + 1);
    Result := S_OK;
  end;
end;

function TRepositoryTreeAccessibility.Get_accDefaultAction(aChild: OleVariant;
  out aAction: WideString): HResult;
begin
  Result := Get_accValue(aChild, aAction);
end;

function TRepositoryTreeAccessibility.accSelect(aFlags: Integer;
  aChild: OleVariant): HResult;
var
  lNode: PVirtualNode;
begin
  Result := ResolveChild(aChild, lNode);
  if Result <> S_OK then
    Exit;
  if (lNode = nil) or ((aFlags and not (SELFLAG_TAKEFOCUS or SELFLAG_TAKESELECTION)) <> 0) then
    Exit(E_INVALIDARG);
  if (aFlags and SELFLAG_TAKESELECTION) <> 0 then
  begin
    fLifetime.Tree.ClearSelection;
    fLifetime.Tree.Selected[lNode] := True;
  end;
  if (aFlags and SELFLAG_TAKEFOCUS) <> 0 then
  begin
    fLifetime.Tree.FocusedNode := lNode;
    if fLifetime.Tree.CanFocus then
      fLifetime.Tree.SetFocus;
  end;
end;

function TRepositoryTreeAccessibility.accLocation(out aLeft, aTop, aWidth,
  aHeight: Integer; aChild: OleVariant): HResult;
var
  lNode: PVirtualNode;
  lRect: TRect;
  lPoint: TPoint;
begin
  aLeft := 0;
  aTop := 0;
  aWidth := 0;
  aHeight := 0;
  Result := ResolveChild(aChild, lNode);
  if Result <> S_OK then
    Exit;
  if lNode = nil then
    lRect := fLifetime.Tree.ClientRect
  else
    lRect := fLifetime.Tree.GetDisplayRect(lNode, NoColumn, False);
  lPoint := fLifetime.Tree.ClientToScreen(lRect.TopLeft);
  aLeft := lPoint.X;
  aTop := lPoint.Y;
  aWidth := lRect.Width;
  aHeight := lRect.Height;
end;

function TRepositoryTreeAccessibility.accNavigate(aDirection: Integer;
  aStart: OleVariant; out aEnd: OleVariant): HResult;
var
  lNode: PVirtualNode;
  lIndex: Integer;
begin
  aEnd := Unassigned;
  Result := ResolveChild(aStart, lNode);
  if Result <> S_OK then
    Exit;
  lIndex := aStart;
  case aDirection of
    NAVDIR_FIRSTCHILD: if lIndex = 0 then lIndex := 1 else Exit(S_FALSE);
    NAVDIR_LASTCHILD: if lIndex = 0 then lIndex := fLifetime.Tree.RootNodeCount else Exit(S_FALSE);
    NAVDIR_NEXT, NAVDIR_DOWN: Inc(lIndex);
    NAVDIR_PREVIOUS, NAVDIR_UP: Dec(lIndex);
  else
    Exit(E_INVALIDARG);
  end;
  if (lIndex < 1) or (Cardinal(lIndex) > fLifetime.Tree.RootNodeCount) then
    Exit(S_FALSE);
  aEnd := lIndex;
  Result := S_OK;
end;

function TRepositoryTreeAccessibility.accHitTest(aLeft, aTop: Integer;
  out aChild: OleVariant): HResult;
var
  lPoint: TPoint;
  lNode: PVirtualNode;
begin
  aChild := Unassigned;
  Result := S_FALSE;
  if fLifetime.Tree = nil then
    Exit;
  lPoint := fLifetime.Tree.ScreenToClient(Point(aLeft, aTop));
  if not PtInRect(fLifetime.Tree.ClientRect, lPoint) then
    Exit;
  aChild := CHILDID_SELF;
  lNode := fLifetime.Tree.GetNodeAt(lPoint);
  if lNode <> nil then
    aChild := Integer(lNode.Index + 1);
  Result := S_OK;
end;

function TRepositoryTreeAccessibility.accDoDefaultAction(aChild: OleVariant): HResult;
begin
  Result := DISP_E_MEMBERNOTFOUND;
end;

function TRepositoryTreeAccessibility.Set_accName(aChild: OleVariant;
  const aName: WideString): HResult;
begin
  Result := E_NOTIMPL;
end;

function TRepositoryTreeAccessibility.Set_accValue(aChild: OleVariant;
  const aValue: WideString): HResult;
begin
  Result := E_NOTIMPL;
end;

function TRepositoryTreeAccessibility.GetIDsOfNames(const aIid: TGUID;
  aNames: Pointer; aCount, aLocale: Integer; aDispIds: Pointer): HResult;
begin
  Result := E_NOTIMPL;
end;

function TRepositoryTreeAccessibility.GetTypeInfo(aIndex, aLocale: Integer;
  out aTypeInfo): HResult;
begin
  Pointer(aTypeInfo) := nil;
  Result := E_NOTIMPL;
end;

function TRepositoryTreeAccessibility.GetTypeInfoCount(out aCount: Integer): HResult;
begin
  aCount := 0;
  Result := S_OK;
end;

function TRepositoryTreeAccessibility.Invoke(aDispId: Integer; const aIid: TGUID;
  aLocale: Integer; aFlags: Word; var aParams; aResult, aException,
  aArgError: Pointer): HResult;
begin
  Result := E_NOTIMPL;
end;

procedure InstallRepositoryAccessibility(const aTree: TVirtualStringTree);
var
  lAccessible: IAccessible;
begin
  lAccessible := TRepositoryTreeAccessibility.Create(aTree);
  aTree.Accessible := lAccessible;
  aTree.AccessibleItem := lAccessible;
end;

end.
