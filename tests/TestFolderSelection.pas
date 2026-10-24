unit TestFolderSelection;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  UFolderSelection;

type
  [TestFixture]
  TFolderSelectionTests = class
  private
    function MakeRule(const aPath: string;
      const aIncluded: Boolean): TFolderSelectionRule;
  public
    [Test]
    procedure EmptyPath_IsNeverIncluded;

    [Test]
    procedure EmptyRules_ExcludeEverything;

    [Test]
    procedure NearestAncestor_ExclusionAndReinclusion;

    [Test]
    procedure ComponentBoundary_DoesNotMatchSiblingPrefix;

    [Test]
    procedure Canonicalization_NormalizesDotsSlashCaseAndRoots;

    [Test]
    procedure UnavailableDriveAndUNCPaths_DoNotRequireFilesystem;

    [Test]
    procedure ParentOverride_ClearsExceptionsAndIncludesFutureChildren;

    [Test]
    procedure RedundantRules_AreRemovedWithoutMutatingInput;

    [Test]
    procedure MixedState_UsesEffectiveDescendantsRegardlessOfOrder;

    [Test]
    procedure SelectedRoots_DeduplicateOverlapsAndKeepIndependentReinclusions;

    [Test]
    procedure EmptyToggle_ReturnsIndependentSnapshot;
  end;

implementation

function TFolderSelectionTests.MakeRule(const aPath: string;
  const aIncluded: Boolean): TFolderSelectionRule;
begin
  Result.Path := aPath;
  Result.Included := aIncluded;
end;

procedure TFolderSelectionTests.EmptyPath_IsNeverIncluded;
var
  lRules: TArray<TFolderSelectionRule>;
begin
  SetLength(lRules, 1);
  lRules[0] := MakeRule('C:\Projects', True);

  Assert.AreEqual('', NormalizeSelectionPath(''));
  Assert.IsFalse(IsSameOrDescendantPath('', 'C:\'));
  Assert.IsFalse(EvaluateFolderSelection('', lRules));
end;

procedure TFolderSelectionTests.EmptyRules_ExcludeEverything;
begin
  Assert.IsFalse(EvaluateFolderSelection('C:\Projects\Repo', []));
end;

procedure TFolderSelectionTests.NearestAncestor_ExclusionAndReinclusion;
var
  lRules: TArray<TFolderSelectionRule>;
begin
  SetLength(lRules, 3);
  lRules[0] := MakeRule('C:\Projects', True);
  lRules[1] := MakeRule('C:\Projects\Archive', False);
  lRules[2] := MakeRule('C:\Projects\Archive\Keep', True);

  Assert.IsTrue(EvaluateFolderSelection('C:\Projects', lRules));
  Assert.IsTrue(EvaluateFolderSelection('C:\Projects\Active\Repo', lRules));
  Assert.IsFalse(EvaluateFolderSelection('C:\Projects\Archive', lRules));
  Assert.IsFalse(EvaluateFolderSelection('C:\Projects\Archive\Old', lRules));
  Assert.IsTrue(EvaluateFolderSelection('C:\Projects\Archive\Keep', lRules));
  Assert.IsTrue(EvaluateFolderSelection('C:\Projects\Archive\Keep\Repo', lRules));
end;

procedure TFolderSelectionTests.ComponentBoundary_DoesNotMatchSiblingPrefix;
var
  lRules: TArray<TFolderSelectionRule>;
begin
  SetLength(lRules, 1);
  lRules[0] := MakeRule('C:\Projects', True);

  Assert.IsTrue(EvaluateFolderSelection('C:\Projects\Repo', lRules));
  Assert.IsTrue(EvaluateFolderSelection('C:\Projects', lRules));
  Assert.IsFalse(EvaluateFolderSelection('C:\Projects2\Repo', lRules));
end;

procedure TFolderSelectionTests.Canonicalization_NormalizesDotsSlashCaseAndRoots;
begin
  Assert.AreEqual('c:\projects\repo',
    NormalizeSelectionPath('C:/Projects/Team/../Repo/.'));
  Assert.AreEqual('c:\', NormalizeSelectionPath('C:/'));
  Assert.AreEqual('\\server\share\',
    NormalizeSelectionPath('\\Server/Share/'));
end;

procedure TFolderSelectionTests.UnavailableDriveAndUNCPaths_DoNotRequireFilesystem;
var
  lRules: TArray<TFolderSelectionRule>;
begin
  SetLength(lRules, 1);
  lRules[0] := MakeRule('Z:\NeverMounted\Root', True);

  Assert.IsTrue(EvaluateFolderSelection('z:/nevermounted/root/child', lRules));

  lRules[0] := MakeRule('\\NoSuchServer\Share\Root', True);
  Assert.IsTrue(EvaluateFolderSelection('\\nosuchserver/share/root/repo', lRules));
end;

procedure TFolderSelectionTests.ParentOverride_ClearsExceptionsAndIncludesFutureChildren;
var
  lRules, lChanged: TArray<TFolderSelectionRule>;
begin
  lRules := [MakeRule('C:\Projects', True), MakeRule('C:\Projects\Archive', False),
    MakeRule('C:\Projects\Archive\Keep', True), MakeRule('C:\Projects2', True)];
  lChanged := SetFolderSelection('C:/PROJECTS/', True, lRules);
  Assert.AreEqual(2, Length(lChanged));
  Assert.IsTrue(EvaluateFolderSelection('C:\Projects\Archive\Future', lChanged));
  Assert.IsTrue(EvaluateFolderSelection('C:\Projects2', lChanged));
  Assert.IsFalse(EvaluateFolderSelection('C:\Projects\Archive\Future', lRules));
  lChanged := SetFolderSelection('C:\Projects', False, lChanged);
  Assert.AreEqual(1, Length(lChanged));
  Assert.AreEqual('c:\projects2', lChanged[0].Path);
  Assert.IsFalse(EvaluateFolderSelection('C:\Projects\Archive\Keep', lChanged));
end;

procedure TFolderSelectionTests.RedundantRules_AreRemovedWithoutMutatingInput;
var
  lRules, lChanged: TArray<TFolderSelectionRule>;
begin
  lRules := [MakeRule('C:\Projects\Child', True), MakeRule('C:\Projects', True),
    MakeRule('C:/PROJECTS/', True), MakeRule('D:\Unchecked', False)];
  lChanged := SetFolderSelection('C:\Projects\New', True, lRules);
  Assert.AreEqual(1, Length(lChanged));
  Assert.AreEqual('c:\projects', lChanged[0].Path);
  lChanged[0].Included := False;
  Assert.IsTrue(lRules[0].Included);
  Assert.IsTrue(lRules[1].Included);
  Assert.AreEqual('C:\Projects', lRules[1].Path);
end;

procedure TFolderSelectionTests.MixedState_UsesEffectiveDescendantsRegardlessOfOrder;
var
  lRules: TArray<TFolderSelectionRule>;
begin
  lRules := [MakeRule('C:\Projects\Archive\Keep', True),
    MakeRule('C:\Projects\Archive', False), MakeRule('C:\Projects', True)];
  Assert.AreEqual(Ord(TFolderSelectionState.fssMixed),
    Ord(GetFolderSelectionState('C:\Projects', lRules)));
  Assert.AreEqual(Ord(TFolderSelectionState.fssMixed),
    Ord(GetFolderSelectionState('C:\Projects\Archive', lRules)));
  Assert.AreEqual(Ord(TFolderSelectionState.fssChecked),
    Ord(GetFolderSelectionState('C:\Projects\Archive\Keep', lRules)));
  Assert.AreEqual(Ord(TFolderSelectionState.fssUnchecked),
    Ord(GetFolderSelectionState('C:\Projects2', lRules)));
  Assert.AreEqual(Ord(TFolderSelectionState.fssMixed),
    Ord(GetFolderSelectionState('C:\', lRules)));
  lRules := [MakeRule('C:\Projects\Child', True), MakeRule('C:\Projects', True)];
  Assert.AreEqual(Ord(TFolderSelectionState.fssChecked),
    Ord(GetFolderSelectionState('C:\Projects', lRules)));
end;

procedure TFolderSelectionTests.SelectedRoots_DeduplicateOverlapsAndKeepIndependentReinclusions;
var
  lRules: TArray<TFolderSelectionRule>;
  lRoots: TArray<string>;
begin
  lRules := [MakeRule('C:\Projects\Archive\Keep', True),
    MakeRule('D:\Archive', False), MakeRule('D:\Archive\Keep', True),
    MakeRule('C:\Projects\Archive', False), MakeRule('C:\Projects', True),
    MakeRule('C:/PROJECTS/', True), MakeRule('C:\Projects2', True)];
  lRoots := SelectedFolderRoots(lRules);
  Assert.AreEqual(3, Length(lRoots));
  Assert.AreEqual('c:\projects', lRoots[0]);
  Assert.AreEqual('c:\projects2', lRoots[1]);
  Assert.AreEqual('d:\archive\keep', lRoots[2]);
  lRoots[0] := 'changed';
  Assert.AreEqual('C:\Projects', lRules[4].Path);
  Assert.AreEqual(0, Length(SelectedFolderRoots([])));
end;

procedure TFolderSelectionTests.EmptyToggle_ReturnsIndependentSnapshot;
var
  lRules, lChanged: TArray<TFolderSelectionRule>;
begin
  lRules := [MakeRule('C:\Projects', True)];
  lChanged := SetFolderSelection('', False, lRules);
  Assert.AreEqual(1, Length(lChanged));
  lChanged[0].Included := False;
  Assert.IsTrue(lRules[0].Included);
  Assert.AreEqual(Ord(TFolderSelectionState.fssUnchecked),
    Ord(GetFolderSelectionState('', lRules)));
end;

initialization
  TDUnitX.RegisterTestFixture(TFolderSelectionTests);

end.
