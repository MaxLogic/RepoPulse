unit TestRepoAccessibility;

interface

uses
  System.SysUtils, System.Types, System.Variants,
  Winapi.ActiveX, Winapi.OleAcc, Winapi.Windows,
  Vcl.Controls, Vcl.Forms,
  VirtualTrees, VirtualTrees.Accessibility, VirtualTrees.Types,
  DUnitX.TestFramework,
  URepositoryAccessibility;

type
  [TestFixture]
  TRepositoryAccessibilityTests = class
  private
    fForm: TForm;
    fTree: TVirtualStringTree;
    fAccessible: IAccessible;
    procedure GetText(aSender: TBaseVirtualTree; aNode: PVirtualNode;
      aColumn: TColumnIndex; aTextType: TVSTTextType; var aCellText: string);
    function NameAt(const aPoint: TPoint): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [TestCase('Path', '18')]
    [TestCase('Status', '48')]
    [TestCase('Action', '36')]
    procedure HitTest_UnfocusedRowUsesScreenCoordinates(const aOffset: Integer);
    [Test]
    procedure Children_ExposeCurrentRowsAndRejectInvalidIds;
    [Test]
    procedure Focus_IsEmptyWhenTreeDoesNotOwnKeyboardFocus;
    [Test]
    procedure Selection_IsIndependentOfKeyboardFocus;
    [Test]
    procedure Bounds_CoverFullRowAndBlankSpaceIsNotARow;
    [Test]
    procedure ScrollAndProjection_ResolveCurrentIdentityWithoutChangingFocus;
    [Test]
    procedure RetainedInterface_RejectsRowsAfterTreeDestruction;
    [Test]
    procedure Navigation_UsesValidSimpleChildIds;
  end;

implementation

procedure TRepositoryAccessibilityTests.GetText(aSender: TBaseVirtualTree;
  aNode: PVirtualNode; aColumn: TColumnIndex; aTextType: TVSTTextType;
  var aCellText: string);
begin
  aCellText := Format('Repository %d. Not analyzed', [aNode.Index]);
end;

procedure TRepositoryAccessibilityTests.Setup;
begin
  fForm := TForm.CreateNew(nil);
  fForm.SetBounds(120, 150, 650, 450);
  fTree := TVirtualStringTree.Create(fForm);
  fTree.Parent := fForm;
  fTree.Align := alClient;
  fTree.Header.Options := [];
  fTree.OnGetText := GetText;
  fTree.AccessibleName := 'Repositories';
  fTree.HandleNeeded;
  fTree.DefaultNodeHeight := 72;
  fTree.RootNodeCount := 3;
  Assert.AreEqual(72, Integer(fTree.DefaultNodeHeight), 'Fixture uses actual72pixel rows');
  fTree.FocusedNode := fTree.GetFirst;
  InstallRepositoryAccessibility(fTree);
  Assert.AreEqual(Integer(S_OK), Integer(AccessibleObjectFromWindow(
    fTree.Handle, DWORD(OBJID_CLIENT), IID_IAccessible, fAccessible)));
end;

procedure TRepositoryAccessibilityTests.TearDown;
begin
  fAccessible := nil;
  fForm.Free;
end;

function TRepositoryAccessibilityTests.NameAt(const aPoint: TPoint): string;
var
  lChild: OleVariant;
  lName: WideString;
  lItem: IAccessible;
begin
  Assert.AreEqual(Integer(S_OK), Integer(fAccessible.accHitTest(aPoint.X,
    aPoint.Y, lChild)), 'A visible row point must resolve');
  if VarIsType(lChild, varDispatch) then
  begin
    lItem := IDispatch(lChild) as IAccessible;
    Assert.AreEqual(Integer(S_OK), Integer(lItem.Get_accName(CHILDID_SELF, lName)));
  end else
    Assert.AreEqual(Integer(S_OK), Integer(fAccessible.Get_accName(lChild, lName)));
  Result := lName;
end;

procedure TRepositoryAccessibilityTests.HitTest_UnfocusedRowUsesScreenCoordinates(
  const aOffset: Integer);
var
  lPoint: TPoint;
  lX: Integer;
begin
  lX := 24;
  if aOffset = 36 then
    lX := fTree.ClientWidth - 24;
  lPoint := fTree.ClientToScreen(Point(lX, 72 + aOffset));
  Assert.AreEqual('Repository 1. Not analyzed', NameAt(lPoint));
  Assert.AreEqual(Cardinal(0), fTree.FocusedNode.Index,
    'Pointer lookup must not move keyboard focus');
end;

procedure TRepositoryAccessibilityTests.Children_ExposeCurrentRowsAndRejectInvalidIds;
var
  lCount: Integer;
  lName: WideString;
begin
  Assert.AreEqual(Integer(S_OK), Integer(fAccessible.Get_accChildCount(lCount)));
  Assert.AreEqual(3, lCount, 'Every current repository has a simple child identity');
  Assert.AreEqual(Integer(S_OK), Integer(fAccessible.Get_accName(2, lName)));
  Assert.AreEqual('Repository 1. Not analyzed', string(lName));
  Assert.AreEqual(Integer(E_INVALIDARG), Integer(fAccessible.Get_accName(99, lName)));
  fTree.RootNodeCount := 1;
  Assert.AreEqual(Integer(S_OK), Integer(fAccessible.Get_accChildCount(lCount)));
  Assert.AreEqual(1, lCount);
  Assert.AreEqual(Integer(E_INVALIDARG), Integer(fAccessible.Get_accName(2, lName)));
end;

procedure TRepositoryAccessibilityTests.Focus_IsEmptyWhenTreeDoesNotOwnKeyboardFocus;
var
  lChild: OleVariant;
begin
  Assert.IsFalse(fTree.Focused, 'Hidden test form has no keyboard focus');
  Assert.AreEqual(Integer(S_OK), Integer(fAccessible.Get_accFocus(lChild)));
  Assert.IsTrue(VarIsEmpty(lChild), 'Unfocused tree must not report an active focused row');
end;

procedure TRepositoryAccessibilityTests.Selection_IsIndependentOfKeyboardFocus;
var
  lChild: OleVariant;
  lName: WideString;
begin
  Assert.AreEqual(Integer(S_OK), Integer(fAccessible.accSelect(SELFLAG_TAKESELECTION, 2)));
  Assert.IsFalse(fTree.Focused, 'Selection must not steal keyboard input focus');
  Assert.AreEqual(Integer(S_OK), Integer(fAccessible.Get_accSelection(lChild)), 'Selection query succeeds independently of focus');
  Assert.AreEqual(Integer(S_OK), Integer(fAccessible.Get_accName(lChild, lName)));
  Assert.AreEqual('Repository 1. Not analyzed', string(lName));
end;

procedure TRepositoryAccessibilityTests.Bounds_CoverFullRowAndBlankSpaceIsNotARow;
var
  lLeft, lTop, lWidth, lHeight: Integer;
  lPoint: TPoint;
  lChild: OleVariant;
begin
  Assert.AreEqual(Integer(S_OK), Integer(fAccessible.accLocation(
    lLeft, lTop, lWidth, lHeight, 2)));
  lPoint := fTree.ClientToScreen(Point(0, 72));
  Assert.AreEqual(lPoint.X, lLeft);
  Assert.AreEqual(lPoint.Y, lTop);
  Assert.AreEqual(fTree.ClientWidth, lWidth, 'Status and action regions belong to the row');
  Assert.AreEqual(72, lHeight);
  lPoint := fTree.ClientToScreen(Point(20, 250));
  Assert.AreEqual(Integer(S_OK), Integer(fAccessible.accHitTest(lPoint.X, lPoint.Y, lChild)));
  Assert.AreEqual(Integer(CHILDID_SELF), Integer(lChild));
  lPoint := fTree.ClientToScreen(Point(-1, 20));
  Assert.AreEqual(Integer(S_FALSE), Integer(fAccessible.accHitTest(lPoint.X, lPoint.Y, lChild)));
  Assert.IsTrue(VarIsEmpty(lChild));
end;

procedure TRepositoryAccessibilityTests.ScrollAndProjection_ResolveCurrentIdentityWithoutChangingFocus;
var
  lRect: TRect;
  lName: WideString;
  lNode: PVirtualNode;
begin
  fTree.RootNodeCount := 40;
  lNode := fTree.GetLast;
  fTree.TopNode := lNode;
  lRect := fTree.GetDisplayRect(lNode, NoColumn, False);
  Assert.IsTrue(lRect.Top >= 0);
  Assert.IsTrue(lRect.Bottom <= fTree.ClientHeight);
  Assert.AreEqual('Repository 39. Not analyzed',
    NameAt(fTree.ClientToScreen(Point(lRect.Left + 24, lRect.Top + 18))));
  Assert.AreEqual(Cardinal(0), fTree.FocusedNode.Index);
  fTree.RootNodeCount := 2;
  fTree.TopNode := fTree.GetFirst;
  Assert.AreEqual(Integer(E_INVALIDARG), Integer(fAccessible.Get_accName(40, lName)));
  Assert.AreEqual('Repository 1. Not analyzed',
    NameAt(fTree.ClientToScreen(Point(24, 90))));
end;

procedure TRepositoryAccessibilityTests.RetainedInterface_RejectsRowsAfterTreeDestruction;
var
  lName: WideString;
  lCount: Integer;
begin
  FreeAndNil(fForm);
  fTree := nil;
  Assert.AreEqual(Integer(E_INVALIDARG), Integer(fAccessible.Get_accName(1, lName)));
  Assert.AreEqual('', string(lName));
  Assert.AreEqual(Integer(E_INVALIDARG), Integer(fAccessible.Get_accChildCount(lCount)));
  Assert.AreEqual(0, lCount);
end;

procedure TRepositoryAccessibilityTests.Navigation_UsesValidSimpleChildIds;
var
  lChild: OleVariant;
  lDispatch: IDispatch;
begin
  Assert.AreEqual(Integer(S_OK), Integer(fAccessible.accNavigate(NAVDIR_FIRSTCHILD, 0, lChild)));
  Assert.AreEqual(1, Integer(lChild));
  Assert.AreEqual(Integer(S_OK), Integer(fAccessible.accNavigate(NAVDIR_NEXT, 1, lChild)));
  Assert.AreEqual(2, Integer(lChild));
  Assert.AreEqual(Integer(S_FALSE), Integer(fAccessible.accNavigate(NAVDIR_NEXT, 3, lChild)));
  Assert.IsTrue(VarIsEmpty(lChild));
  Assert.AreEqual(Integer(S_FALSE), Integer(fAccessible.Get_accChild(2, lDispatch)));
  Assert.IsTrue(lDispatch = nil, 'Rows are simple children, not allocated child COM objects');
  Assert.AreEqual(Integer(E_INVALIDARG), Integer(fAccessible.accSelect(SELFLAG_EXTENDSELECTION, 2)));
end;

initialization
  TDUnitX.RegisterTestFixture(TRepositoryAccessibilityTests);

end.
