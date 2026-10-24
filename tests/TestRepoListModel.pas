unit TestRepoListModel;

interface

uses
  System.SysUtils,
  AutoFree, DUnitX.TestFramework,
  UFolderSelection, UModels, URepoListModel;

type
  [TestFixture]
  TRepoListModelTests = class
  private
    function MakeStatus(const aIndex: Integer; const aProblem, aDirty, aBehind: Boolean): TRepoStatus;
  public
    [Test]
    procedure Projection_HandlesOneThousandItems;
    [Test]
    procedure VisibleRoots_CapturesEveryMatchingIdentityIndependently;
    [Test]
    procedure ReconcileInventory_RetainsCommittedStatusAndRebuildsProjection;
    [Test]
    procedure AddOrUpdate_PreservesIdentityAndChangesMembership;
    [Test]
    procedure SelectionRoot_SurvivesProjectionChanges;
    [Test]
    procedure WaitingItem_IsVisibleUntilStatusArrives;
    [Test]
    procedure AheadFilter_ShowsOnlyRepositoriesAheadOfUpstream;
    [Test]
    procedure ActionableFilters_MatchApprovedTaxonomy;
    [Test]
    procedure UnrelatedHistory_IsExclusiveAndNotPullable;
    [Test]
    procedure VisibleActionRoots_HonorCurrentProjection;
    [Test]
    procedure Projection_SortsStreamedAndUpdatedDisplayPaths;
    [TestCase('Cached', 'True,False')]
    [TestCase('Failed', 'False,True')]
    procedure StaleStatus_RemainsFilterableButCannotMutate(const aCached, aFailed: Boolean);
    [TestCase('Suffix', 'C:\Repos\Alpha-workspace,*-workspace,True')]
    [TestCase('Suffix case', 'c:\repos\ALPHA-WORKSPACE,*-workspace,True')]
    [TestCase('Suffix boundary', 'C:\Repos\Alpha-workspace-copy,*-workspace,False')]
    [TestCase('Obsolete root', 'C:\Repos\_obselete,*\_obselete\*,True')]
    [TestCase('Obsolete child', 'C:\Repos\_obselete\Alpha,*\_obselete\*,True')]
    [TestCase('Obsolete boundary', 'C:\Repos\_obselete-copy\Alpha,*\_obselete\*,False')]
    [TestCase('Slash case', 'C:/Repos/_OBSELETE/Alpha,*\_obselete\*,True')]
    [TestCase('UNC', '\\server\share\_obselete\Alpha,*\_obselete\*,True')]
    [TestCase('Question', 'C:\Repos\Alpha1,Alpha?,True')]
    [TestCase('Question length', 'C:\Repos\Alpha12,Alpha?,False')]
    [TestCase('Literal brackets', 'C:\Repos\[Alpha],[Alpha],True')]
    [TestCase('No negation', 'C:\Repos\Alpha,!Alpha,False')]
    [TestCase('Blank', 'C:\Repos\Alpha, ,False')]
    [TestCase('Literal hash', 'C:\Repos\#Alpha,#Alpha,True')]
    [TestCase('Literal bang', 'C:\Repos\!Alpha,!Alpha,True')]
    procedure Exclusions_MatchNameAndPath(const aRoot, aPattern: string; const aExcluded: Boolean);
    [Test]
    procedure SearchAndExclusions_UseOneRetainedProjection;
    [Test]
    procedure Exclusions_PreserveLiteralSpaces;
    [Test]
    procedure PathSelection_IntersectsFiltersAndRetainsHiddenRows;
    [Test]
    procedure PathSelection_EmptyRulesHideAllKnownRoots;
    [TestCase('Boolean and exclusion', '0')]
    [TestCase('Quoted phrase', '1')]
    [TestCase('Question wildcard', '2')]
    procedure SearchSyntax_PreservesDiscoveryCharacterization(const aCaseIndex: Integer);
  end;

implementation

procedure TRepoListModelTests.PathSelection_EmptyRulesHideAllKnownRoots;
var
  lModel: TRepoListModel;
begin
  lModel := TRepoListModel.Create;
  try
    lModel.AddWaiting('C:\Repos\Known', 'Known');
    lModel.SetPathSelection([]);
    Assert.AreEqual(0, lModel.VisibleCount, 'No checked scope means no visible repositories');
    Assert.AreEqual(1, lModel.Count, 'Path selection must never discard known identities');
  finally
    lModel.Free;
  end;
end;

procedure TRepoListModelTests.PathSelection_IntersectsFiltersAndRetainsHiddenRows;
var
  lModel: TRepoListModel;
  lRules: TArray<TFolderSelectionRule>;
  lStatus: TRepoStatus;
begin
  lModel := TRepoListModel.Create;
  try
    lStatus := MakeStatus(1, True, True, True);
    lStatus.RepoRoot := 'C:\Repos\Keep';
    lModel.AddOrUpdate(lStatus, 'Keep');
    lStatus.RepoRoot := 'C:\Other\Keep';
    lModel.AddOrUpdate(lStatus, 'Keep elsewhere');
    lStatus.RepoRoot := 'C:\Repos\Keep-workspace';
    lModel.AddOrUpdate(lStatus, 'Keep-workspace');
    lStatus.RepoRoot := 'C:\Repos\Different';
    lModel.AddOrUpdate(lStatus, 'Different');
    lModel.SetSearchQuery('Keep');
    lModel.SetExclusions(['*-workspace']);
    SetLength(lRules, 1);
    lRules[0].Path := 'C:\Repos';
    lRules[0].Included := True;
    lModel.SetPathSelection(lRules);
    Assert.AreEqual(1, lModel.VisibleCount);
    Assert.AreEqual(1, lModel.FilterCount(TRepoListFilter.rlfAll));
    Assert.AreEqual(1, Length(lModel.VisibleActionRoots(TRepoListAction.rlaPull)));
    Assert.AreEqual('C:\Repos\Keep', lModel.VisibleActionRoots(TRepoListAction.rlaPush)[0]);
    lRules[0].Included := False;
    lModel.SetSearchQuery('Keep');
    Assert.AreEqual(1, lModel.VisibleCount, 'The model owns an immutable copy of path rules');
    lModel.SetPathSelection([]);
    Assert.AreEqual(0, lModel.VisibleCount);
    Assert.AreEqual(4, lModel.Count);
    lRules[0].Included := True;
    lModel.SetPathSelection(lRules);
    Assert.AreEqual(1, lModel.VisibleCount, 'Changing scope reveals retained identities');
  finally
    lModel.Free;
  end;
end;

procedure TRepoListModelTests.Exclusions_PreserveLiteralSpaces;
var
  lModel: TRepoListModel;
begin
  lModel := TRepoListModel.Create;
  try
    lModel.AddWaiting('C:\Repos\ Alpha', ' Alpha');
    lModel.AddWaiting('C:\Repos\Alpha', 'Alpha');
    lModel.SetExclusions([' Alpha*']);
    Assert.AreEqual(1, lModel.VisibleCount);
    Assert.AreEqual('C:\Repos\Alpha', lModel.ItemAtVisible(0).RepoRoot,
      'Whitespace in a nonblank glob is literal');
  finally
    lModel.Free;
  end;
end;

procedure TRepoListModelTests.Exclusions_MatchNameAndPath(const aRoot, aPattern: string;
  const aExcluded: Boolean);
var
  lModel: TRepoListModel;
begin
  lModel := TRepoListModel.Create;
  try
    lModel.AddWaiting(aRoot, aRoot);
    Assert.AreEqual(Integer(Ord(aExcluded)), Length(lModel.PreviewExcludedRoots([aPattern])));
    Assert.AreEqual(1, lModel.VisibleCount, 'Preview must leave the active projection unchanged');
    lModel.SetExclusions([aPattern]);
    Assert.AreEqual(1 - Ord(aExcluded), lModel.VisibleCount);
    Assert.AreEqual(1, lModel.Count, 'Excluded repositories remain known');
    lModel.SetExclusions([]);
    Assert.AreEqual(1, lModel.VisibleCount);
  finally
    lModel.Free;
  end;
end;

procedure TRepoListModelTests.SearchAndExclusions_UseOneRetainedProjection;
var
  lModel: TRepoListModel;
  lStatus: TRepoStatus;
begin
  lModel := TRepoListModel.Create;
  try
    lStatus := MakeStatus(1, True, True, True);
    lStatus.RepoRoot := 'C:\Repos\Alpha';
    lModel.AddOrUpdate(lStatus, 'Alpha');
    lStatus.RepoRoot := 'C:\Repos\Beta-workspace';
    lModel.AddOrUpdate(lStatus, 'Beta-workspace');
    lStatus.RepoRoot := 'C:\Repos\Gamma';
    lModel.AddOrUpdate(lStatus, 'Gamma');
    lModel.SetSearchQuery('alpha|beta !gamma');
    Assert.AreEqual(2, lModel.VisibleCount, 'Foundation OR/AND/negation syntax must remain live');
    lModel.SetExclusions(['*-workspace']);
    Assert.AreEqual(1, lModel.VisibleCount);
    Assert.AreEqual(1, lModel.FilterCount(TRepoListFilter.rlfAll));
    Assert.AreEqual(1, Length(lModel.VisibleActionRoots(TRepoListAction.rlaPull)));
    Assert.AreEqual('C:\Repos\Alpha', lModel.VisibleActionRoots(TRepoListAction.rlaPush)[0]);
    lStatus.RepoRoot := 'C:\Repos\Delta';
    lModel.AddOrUpdate(lStatus, 'Delta');
    Assert.AreEqual(1, lModel.VisibleCount, 'New results use the active predicates');
    lModel.SetSearchQuery('   ');
    Assert.AreEqual(3, lModel.VisibleCount);
    lModel.SetExclusions([]);
    Assert.AreEqual(4, lModel.VisibleCount);
    Assert.AreEqual(4, lModel.Count);
  finally
    lModel.Free;
  end;
end;

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

procedure TRepoListModelTests.StaleStatus_RemainsFilterableButCannotMutate(
  const aCached, aFailed: Boolean);
var
  lModel: TRepoListModel;
  lStatus: TRepoStatus;
begin
  lModel := TRepoListModel.Create;
  try
    lStatus := MakeStatus(1, True, True, True);
    lStatus.IsCached := aCached;
    lStatus.ScanFailed := aFailed;
    lModel.AddOrUpdate(lStatus, 'Saved status');
    lModel.SetFilter(TRepoListFilter.rlfDirty);
    Assert.AreEqual(1, lModel.VisibleCount, 'Saved status must remain usable by filters');
    Assert.IsFalse(lModel.HasVisibleAction(TRepoListAction.rlaPull), 'Saved status cannot authorize Pull');
    Assert.IsFalse(lModel.HasVisibleAction(TRepoListAction.rlaPush), 'Saved status cannot authorize Push');
    Assert.AreEqual(0, Length(lModel.VisibleActionRoots(TRepoListAction.rlaPull)));
    Assert.AreEqual(0, Length(lModel.VisibleActionRoots(TRepoListAction.rlaPush)));
    lStatus.IsCached := False;
    lStatus.ScanFailed := False;
    lModel.AddOrUpdate(lStatus, 'Fresh status');
    Assert.IsTrue(lModel.HasVisibleAction(TRepoListAction.rlaPull));
    Assert.IsTrue(lModel.HasVisibleAction(TRepoListAction.rlaPush));
  finally
    lModel.Free;
  end;
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
    lModel.SetFilter(TRepoListFilter.rlfNoIssues);
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

procedure TRepoListModelTests.AheadFilter_ShowsOnlyRepositoriesAheadOfUpstream;
var
  lAheadStatus: TRepoStatus;
  lDivergedStatus: TRepoStatus;
  lModel: TRepoListModel;
  lSyncedStatus: TRepoStatus;
begin
  lModel := TRepoListModel.Create;
  try
    lAheadStatus := MakeStatus(1, True, False, False);
    lAheadStatus.Ahead := 2;
    lAheadStatus.HasUnpushed := True;
    lModel.AddOrUpdate(lAheadStatus, 'Ahead');
    lDivergedStatus := MakeStatus(3, True, False, True);
    lDivergedStatus.Ahead := 1;
    lModel.AddOrUpdate(lDivergedStatus, 'Diverged');
    lSyncedStatus := MakeStatus(2, False, False, False);
    lModel.AddOrUpdate(lSyncedStatus, 'Synced');

    lModel.SetFilter(TRepoListFilter.rlfAhead);

    Assert.AreEqual(1, lModel.VisibleCount);
    Assert.AreEqual(lAheadStatus.RepoRoot, lModel.ItemAtVisible(0).RepoRoot);
  finally
    lModel.Free;
  end;
end;

procedure TRepoListModelTests.ActionableFilters_MatchApprovedTaxonomy;
var
  lModel: TRepoListModel;
  lStatus: TRepoStatus;
begin
  lModel := TRepoListModel.Create;
  try
    lStatus := MakeStatus(1, True, False, True);
    lModel.AddOrUpdate(lStatus, 'Ready to pull');

    lStatus := MakeStatus(2, True, True, True);
    lModel.AddOrUpdate(lStatus, 'Behind and dirty');

    lStatus := MakeStatus(3, True, False, True);
    lStatus.Ahead := 1;
    lModel.AddOrUpdate(lStatus, 'Diverged');

    lStatus := MakeStatus(4, True, False, False);
    lStatus.Ahead := 2;
    lModel.AddOrUpdate(lStatus, 'Ahead only');

    lStatus := MakeStatus(5, False, False, False);
    lStatus.LastPullError := 'pull failed';
    lModel.AddOrUpdate(lStatus, 'Pull failed');

    lStatus := MakeStatus(6, False, False, False);
    lStatus.LastPushError := 'push failed';
    lModel.AddOrUpdate(lStatus, 'Push failed');

    lStatus := MakeStatus(7, False, False, False);
    lStatus.ScanFailed := True;
    lStatus.ScanError := 'scan failed';
    lModel.AddOrUpdate(lStatus, 'Scan failed');

    lStatus := MakeStatus(8, True, False, False);
    lStatus.Branch := '(detached)';
    lModel.AddOrUpdate(lStatus, 'Detached');

    lModel.AddOrUpdate(MakeStatus(9, False, False, False), 'No issues');
    lModel.AddWaiting('C:\Repos\Waiting', 'Waiting');

    Assert.AreEqual(9, lModel.FilterCount(TRepoListFilter.rlfAttention));
    Assert.AreEqual(2, lModel.FilterCount(TRepoListFilter.rlfOperationFailed));
    Assert.AreEqual(1, lModel.FilterCount(TRepoListFilter.rlfScanFailed));
    Assert.AreEqual(1, lModel.FilterCount(TRepoListFilter.rlfReadyToPull));
    Assert.AreEqual(2, lModel.FilterCount(TRepoListFilter.rlfBehindOnly));
    Assert.AreEqual(1, lModel.FilterCount(TRepoListFilter.rlfDiverged));
    Assert.AreEqual(1, lModel.FilterCount(TRepoListFilter.rlfAhead));
    Assert.AreEqual(1, lModel.FilterCount(TRepoListFilter.rlfDirty));
    Assert.AreEqual(1, lModel.FilterCount(TRepoListFilter.rlfDetached));
    Assert.AreEqual(1, lModel.FilterCount(TRepoListFilter.rlfNoIssues));
    Assert.AreEqual(10, lModel.FilterCount(TRepoListFilter.rlfAll));
  finally
    lModel.Free;
  end;
end;

procedure TRepoListModelTests.UnrelatedHistory_IsExclusiveAndNotPullable;
var
  lModel: TRepoListModel;
  lStatus: TRepoStatus;
begin
  lModel := TRepoListModel.Create;
  try
    lStatus := MakeStatus(11, False, False, True);
    lStatus.Ahead := 7;
    lStatus.UnrelatedHistory := True;
    lModel.AddOrUpdate(lStatus, 'Unrelated');

    lModel.SetFilter(TRepoListFilter.rlfUnrelatedHistory);
    Assert.AreEqual(1, lModel.VisibleCount);
    Assert.IsFalse(lModel.HasVisibleAction(TRepoListAction.rlaPull),
      'Pull all must not touch a repository with unrelated history');
    lModel.SetFilter(TRepoListFilter.rlfAttention);
    Assert.AreEqual(1, lModel.VisibleCount,
      'Unrelated history needs attention even when a stale producer omitted HasProblem');
    lModel.SetFilter(TRepoListFilter.rlfDiverged);
    Assert.AreEqual(0, lModel.VisibleCount,
      'Unrelated history must not also appear as diverged');
    lModel.SetFilter(TRepoListFilter.rlfNoIssues);
    Assert.AreEqual(0, lModel.VisibleCount);
  finally
    lModel.Free;
  end;
end;

procedure TRepoListModelTests.VisibleActionRoots_HonorCurrentProjection;
var
  lModel: TRepoListModel;
  lPullRoots: TArray<string>;
  lPushRoots: TArray<string>;
  lStatus: TRepoStatus;
begin
  lModel := TRepoListModel.Create;
  try
    lStatus := MakeStatus(1, True, True, True);
    lModel.AddOrUpdate(lStatus, 'Visible pull and push');
    lStatus := MakeStatus(2, True, False, True);
    lModel.AddOrUpdate(lStatus, 'Hidden pull');
    lStatus := MakeStatus(3, True, True, False);
    lModel.AddOrUpdate(lStatus, 'Visible push');
    lModel.AddWaiting('C:\Repos\Waiting', 'Waiting');
    lModel.SetFilter(TRepoListFilter.rlfDirty);

    lPullRoots := lModel.VisibleActionRoots(TRepoListAction.rlaPull);
    lPushRoots := lModel.VisibleActionRoots(TRepoListAction.rlaPush);

    Assert.IsTrue(lModel.HasVisibleAction(TRepoListAction.rlaPull));
    Assert.IsTrue(lModel.HasVisibleAction(TRepoListAction.rlaPush));
    Assert.AreEqual(1, Length(lPullRoots));
    Assert.AreEqual('C:\Repos\Repo0001', lPullRoots[0]);
    Assert.AreEqual(2, Length(lPushRoots));
    Assert.AreEqual('C:\Repos\Repo0001', lPushRoots[0]);
    Assert.AreEqual('C:\Repos\Repo0003', lPushRoots[1]);
    lModel.SetFilter(TRepoListFilter.rlfNoIssues);
    Assert.IsFalse(lModel.HasVisibleAction(TRepoListAction.rlaPull));
    Assert.IsFalse(lModel.HasVisibleAction(TRepoListAction.rlaPush));
  finally
    lModel.Free;
  end;
end;

procedure TRepoListModelTests.Projection_SortsStreamedAndUpdatedDisplayPaths;
var
  lModel: TRepoListModel;
  lStatus: TRepoStatus;
begin
  lModel := TRepoListModel.Create;
  try
    lModel.AddWaiting('C:\Repos\Zeta', 'zeta');
    lModel.AddWaiting('C:\Repos\Alpha', 'Alpha');
    lModel.AddWaiting('C:\Repos\Middle', 'middle');

    Assert.AreEqual('Alpha', lModel.ItemAtVisible(0).DisplayPath);
    Assert.AreEqual('middle', lModel.ItemAtVisible(1).DisplayPath);
    Assert.AreEqual('zeta', lModel.ItemAtVisible(2).DisplayPath);

    lStatus := MakeStatus(99, True, False, True);
    lStatus.RepoRoot := 'C:\Repos\Zeta';
    lModel.AddOrUpdate(lStatus, 'Beta');

    Assert.AreEqual('Alpha', lModel.ItemAtVisible(0).DisplayPath);
    Assert.AreEqual('Beta', lModel.ItemAtVisible(1).DisplayPath);
    Assert.AreEqual('middle', lModel.ItemAtVisible(2).DisplayPath);
    lModel.SetFilter(TRepoListFilter.rlfAll);
    Assert.AreEqual('Alpha', lModel.ItemAtVisible(0).DisplayPath);
    Assert.AreEqual('Beta', lModel.ItemAtVisible(1).DisplayPath);
    Assert.AreEqual('middle', lModel.ItemAtVisible(2).DisplayPath);
  finally
    lModel.Free;
  end;
end;

procedure TRepoListModelTests.VisibleRoots_CapturesEveryMatchingIdentityIndependently;
var
  g: TGarbos;
  lModel: TRepoListModel;
  lStatus: TRepoStatus;
  lRules: TArray<TFolderSelectionRule>;
  lCaptured: TArray<string>;
  i: Integer;
begin
  GC(lModel, TRepoListModel.Create, g);
  lModel.SetFilter(TRepoListFilter.rlfAll);
  for i := 1 to 80 do
  begin
    lStatus := MakeStatus(i, False, False, False);
    lStatus.IsCached := True;
    if Odd(i) then
      lModel.AddOrUpdate(lStatus, lStatus.RepoRoot)
    else
      lModel.AddWaiting(lStatus.RepoRoot, lStatus.RepoRoot);
  end;
  lModel.AddWaiting('C:\Outside\RepoHidden', 'Outside');
  SetLength(lRules, 1);
  lRules[0].Path := 'C:\Repos';
  lRules[0].Included := True;
  lModel.SetPathSelection(lRules);
  lModel.SetExclusions(['Repo0010', 'Repo0020']);
  lModel.SetSearchQuery('Repo');
  lCaptured := lModel.VisibleRoots;
  Assert.AreEqual(78, Length(lCaptured), 'Analysis includes cached, waiting and offscreen matching rows');
  Assert.AreEqual('C:\Repos\Repo0001', lCaptured[0]);
  Assert.AreEqual('C:\Repos\Repo0002', lCaptured[1]);
  Assert.AreEqual('C:\Repos\Repo0080', lCaptured[77]);
  lCaptured[0] := 'changed snapshot';
  Assert.AreEqual('C:\Repos\Repo0001', lModel.VisibleRoots[0], 'Caller cannot mutate the model through its snapshot');
  lCaptured[0] := 'C:\Repos\Repo0001';
  lModel.SetSearchQuery('Repo0001');
  Assert.AreEqual(1, Length(lModel.VisibleRoots));
  lModel.SetPathSelection([]);
  lModel.AddWaiting('C:\Repos\Repo9999', 'Newly discovered');
  Assert.AreEqual(0, Length(lModel.VisibleRoots));
  Assert.AreEqual(78, Length(lCaptured), 'Captured analysis scope survives later filters and additions');
  Assert.AreEqual('C:\Repos\Repo0080', lCaptured[77]);
end;

procedure TRepoListModelTests.ReconcileInventory_RetainsCommittedStatusAndRebuildsProjection;
var
  g: TGarbos;
  lModel: TRepoListModel;
  lStatus: TRepoStatus;
  lItem: TRepoListItem;
begin
  GC(lModel, TRepoListModel.Create, g);
  lModel.SetFilter(TRepoListFilter.rlfAll);
  lStatus := MakeStatus(1, True, True, True);
  lStatus.RepoRoot := 'C:\Repos\Keep';
  lStatus.Branch := 'retained-branch';
  lStatus.IsCached := True;
  lStatus.LastAnalyzedUtc := '2026-09-19T10:11:12Z';
  lModel.AddOrUpdate(lStatus, 'A retained display');
  lStatus.RepoRoot := 'C:\Repos\Hidden';
  lModel.AddOrUpdate(lStatus, 'Z hidden display');
  lModel.AddWaiting('C:\Repos\Keep-Provisional', 'B provisional');
  lModel.SetSearchQuery('Keep');
  lModel.ReconcileInventory(['c:\repos\keep', 'C:\Repos\Hidden', 'C:\Repos\Keep-New',
    'C:\REPOS\KEEP-NEW', '']);
  Assert.AreEqual(3, lModel.Count, 'Exact committed identities replace provisional membership');
  Assert.AreEqual(2, lModel.VisibleCount, 'Current search is preserved and missing committed roots are waiting');
  Assert.AreEqual(-1, lModel.FindVisibleIndex('C:\Repos\Keep-Provisional'));
  lItem := lModel.ItemAtVisible(lModel.FindVisibleIndex('C:\Repos\Keep'));
  Assert.AreEqual('A retained display', lItem.DisplayPath);
  Assert.AreEqual(Integer(TRepoListItemState.rlisReady), Integer(lItem.State));
  Assert.AreEqual('retained-branch', lItem.Status.Branch);
  Assert.AreEqual('2026-09-19T10:11:12Z', lItem.Status.LastAnalyzedUtc);
  Assert.IsTrue(lItem.Status.IsCached);
  Assert.IsTrue(lItem.Status.IsDirty);
  lItem := lModel.ItemAtVisible(lModel.FindVisibleIndex('C:\Repos\Keep-New'));
  Assert.AreEqual(Integer(TRepoListItemState.rlisWaiting), Integer(lItem.State));
  lModel.SetSearchQuery('');
  Assert.AreEqual('C:\Repos\Keep', lModel.ItemAtVisible(0).RepoRoot);
  Assert.AreEqual('C:\Repos\Hidden', lModel.ItemAtVisible(2).RepoRoot);
  lStatus.Branch := 'updated-after-reconcile';
  lModel.AddOrUpdate(lStatus, 'Z hidden display');
  Assert.AreEqual(3, lModel.Count, 'Rebuilt root index updates retained hidden identities');
  Assert.AreEqual('updated-after-reconcile', lModel.ItemAtVisible(2).Status.Branch);
  lModel.AddWaiting('C:\Repos\Keep-Provisional', 'B rediscovered');
  Assert.AreEqual(4, lModel.Count, 'Removed provisional root can be re-added without a stale index');
  Assert.AreEqual(1, lModel.FindVisibleIndex('C:\Repos\Keep-Provisional'));
  lModel.ReconcileInventory([]);
  Assert.AreEqual(0, lModel.Count);
  Assert.AreEqual(0, lModel.VisibleCount);
end;

procedure TRepoListModelTests.SearchSyntax_PreservesDiscoveryCharacterization(const aCaseIndex: Integer);
const
  cQueries: array[0..2] of string = ('alpha|beta !archive', '"team alpha"', 'beta?ore');
  cExpectedCounts: array[0..2] of Integer = (3, 1, 1);
  cFirstRoots: array[0..2] of string = ('C:\Repos\AlphaTools', 'C:\Repos\Team Alpha', 'C:\Repos\BetaCore');
var
  g: TGarbos;
  lModel: TRepoListModel;
  lRoots: TArray<string>;
begin
  GC(lModel, TRepoListModel.Create, g);
  lModel.AddWaiting('C:\Repos\AlphaTools', 'AlphaTools');
  lModel.AddWaiting('C:\Repos\AlphaArchive', 'AlphaArchive');
  lModel.AddWaiting('C:\Repos\BetaCore', 'BetaCore');
  lModel.AddWaiting('C:\Repos\Team Alpha', 'Team Alpha');
  lModel.SetSearchQuery(cQueries[aCaseIndex]);
  lRoots := lModel.VisibleRoots;
  Assert.AreEqual(cExpectedCounts[aCaseIndex], Length(lRoots));
  Assert.AreEqual(cFirstRoots[aCaseIndex], lRoots[0]);
  if aCaseIndex = 0 then
  begin
    Assert.AreEqual('C:\Repos\BetaCore', lRoots[1]);
    Assert.AreEqual('C:\Repos\Team Alpha', lRoots[2]);
  end;
  Assert.AreEqual(4, lModel.Count, 'Search affects projection, never retained inventory');
end;

initialization
  TDUnitX.RegisterTestFixture(TRepoListModelTests);

end.
