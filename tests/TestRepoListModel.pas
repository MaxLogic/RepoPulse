unit TestRepoListModel;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  UModels, URepoListModel;

type
  [TestFixture]
  TRepoListModelTests = class
  private
    function MakeStatus(const aIndex: Integer; const aProblem, aDirty, aBehind: Boolean): TRepoStatus;
  public
    [Test]
    procedure Projection_HandlesOneThousandItems;
    [Test]
    procedure AddOrUpdate_PreservesIdentityAndChangesMembership;
    [Test]
    procedure SelectionRoot_SurvivesProjectionChanges;
    [Test]
    procedure WaitingItem_IsVisibleUntilStatusArrives;
  end;

implementation

function TRepoListModelTests.MakeStatus(const aIndex: Integer;
  const aProblem, aDirty, aBehind: Boolean): TRepoStatus;
begin
  Result := Default(TRepoStatus);
  Result.RepoRoot := Format('C:\Repos\Repo%.4d', [aIndex]);
  Result.Branch := 'main';
  Result.HasProblem := aProblem;
  Result.IsDirty := aDirty;
  Result.IsOutOfDate := aBehind;
  if aBehind then
    Result.Behind := 1;
end;

procedure TRepoListModelTests.Projection_HandlesOneThousandItems;
var
  lModel: TRepoListModel;
  lStatus: TRepoStatus;
  i: Integer;
begin
  lModel := TRepoListModel.Create;
  try
    for i := 0 to 999 do
    begin
      lStatus := MakeStatus(i, Odd(i), (i mod 3) = 0, (i mod 5) = 0);
      lModel.AddOrUpdate(lStatus, Format('Repo%.4d', [i]));
    end;

    Assert.AreEqual(1000, lModel.Count);
    Assert.AreEqual(500, lModel.VisibleCount);
    Assert.AreEqual('C:\Repos\Repo0001', lModel.ItemAtVisible(0).RepoRoot);
    lModel.SetFilter(TRepoListFilter.rlfAll);
    Assert.AreEqual(1000, lModel.VisibleCount);
  finally
    lModel.Free;
  end;
end;

procedure TRepoListModelTests.AddOrUpdate_PreservesIdentityAndChangesMembership;
var
  lModel: TRepoListModel;
  lStatus: TRepoStatus;
begin
  lModel := TRepoListModel.Create;
  try
    lStatus := MakeStatus(7, True, False, True);
    lModel.AddOrUpdate(lStatus, 'First display');
    Assert.AreEqual(1, lModel.Count);
    Assert.AreEqual(1, lModel.VisibleCount);

    lStatus := MakeStatus(7, False, False, False);
    lModel.AddOrUpdate(lStatus, 'Updated display');
    Assert.AreEqual(1, lModel.Count);
    Assert.AreEqual(0, lModel.VisibleCount);
    lModel.SetFilter(TRepoListFilter.rlfAll);
    Assert.AreEqual('Updated display', lModel.ItemAtVisible(0).DisplayPath);
  finally
    lModel.Free;
  end;
end;

procedure TRepoListModelTests.SelectionRoot_SurvivesProjectionChanges;
var
  lModel: TRepoListModel;
  lSelectedRoot: string;
begin
  lModel := TRepoListModel.Create;
  try
    lModel.AddOrUpdate(MakeStatus(1, True, False, True), 'One');
    lModel.AddOrUpdate(MakeStatus(2, False, False, False), 'Two');
    lSelectedRoot := 'c:\repos\REPO0001';

    Assert.AreEqual(0, lModel.FindVisibleIndex(lSelectedRoot));
    lModel.SetFilter(TRepoListFilter.rlfAll);
    Assert.AreEqual(0, lModel.FindVisibleIndex(lSelectedRoot));
    lModel.SetFilter(TRepoListFilter.rlfClean);
    Assert.AreEqual(-1, lModel.FindVisibleIndex(lSelectedRoot));
  finally
    lModel.Free;
  end;
end;

procedure TRepoListModelTests.WaitingItem_IsVisibleUntilStatusArrives;
var
  lModel: TRepoListModel;
  lItem: TRepoListItem;
  lStatus: TRepoStatus;
begin
  lModel := TRepoListModel.Create;
  try
    lStatus := MakeStatus(9, False, False, False);
    lModel.AddWaiting(lStatus.RepoRoot, 'Waiting');
    Assert.AreEqual(1, lModel.VisibleCount);
    lItem := lModel.ItemAtVisible(0);
    Assert.AreEqual(TRepoListItemState.rlisWaiting, lItem.State);

    lModel.AddOrUpdate(lStatus, 'Ready');
    Assert.AreEqual(1, lModel.Count);
    Assert.AreEqual(0, lModel.VisibleCount);
    lModel.SetFilter(TRepoListFilter.rlfAll);
    lItem := lModel.ItemAtVisible(0);
    Assert.AreEqual(TRepoListItemState.rlisReady, lItem.State);
    Assert.AreEqual('Ready', lItem.DisplayPath);
  finally
    lModel.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRepoListModelTests);

end.
