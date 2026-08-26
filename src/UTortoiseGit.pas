unit UTortoiseGit;

interface

uses
  System.IOUtils, System.SysUtils,

  Winapi.Windows;

type
  {$SCOPEDENUMS ON}
  TTortoiseGitCommand = (tgcCommit, tgcSync);

  TTortoiseGit = class sealed
  private
    class procedure AddCandidate(var aCandidates: TArray<string>; const aValue: string); static;
    class procedure AddRegistryCandidates(var aCandidates: TArray<string>); static;
    class procedure AddRegistryKeyCandidates(var aCandidates: TArray<string>; const aRootKey: HKEY;
      const aAccess: LongWord); static;
  public
    class function BuildParameters(const aCommand: TTortoiseGitCommand;
      const aRepoRoot: string): string; static;
    class function ResolveExecutable(const aCandidates: TArray<string>;
      const aPathValue: string): string; static;
    class function DetectExecutable: string; static;
    class function TryLaunch(const aExecutable: string; const aCommand: TTortoiseGitCommand;
      const aRepoRoot: string; out aError: string): Boolean; static;
  end;

implementation

uses
  System.Win.Registry,

  Winapi.ShellAPI;

resourcestring
  rsLaunchFailed = 'TortoiseGit failed to start (code %d).';

class procedure TTortoiseGit.AddCandidate(var aCandidates: TArray<string>; const aValue: string);
var
  lIndex: Integer;
begin
  if Trim(aValue) = '' then
    Exit;
  lIndex := Length(aCandidates);
  SetLength(aCandidates, lIndex + 1);
  aCandidates[lIndex] := Trim(aValue);
end;

class procedure TTortoiseGit.AddRegistryCandidates(var aCandidates: TArray<string>);
begin
  AddRegistryKeyCandidates(aCandidates, HKEY_LOCAL_MACHINE, KEY_READ or KEY_WOW64_64KEY);
  AddRegistryKeyCandidates(aCandidates, HKEY_LOCAL_MACHINE, KEY_READ or KEY_WOW64_32KEY);
  AddRegistryKeyCandidates(aCandidates, HKEY_CURRENT_USER, KEY_READ);
end;

class procedure TTortoiseGit.AddRegistryKeyCandidates(var aCandidates: TArray<string>;
  const aRootKey: HKEY; const aAccess: LongWord);
var
  lRegistry: TRegistry;
begin
  lRegistry := TRegistry.Create(aAccess);
  try
    lRegistry.RootKey := aRootKey;
    if lRegistry.OpenKeyReadOnly('SOFTWARE\TortoiseGit') then
    begin
      try
        if lRegistry.ValueExists('ProcPath') then
          AddCandidate(aCandidates, lRegistry.ReadString('ProcPath'));
        if lRegistry.ValueExists('Directory') then
          AddCandidate(aCandidates, lRegistry.ReadString('Directory'));
      finally
        lRegistry.CloseKey;
      end;
    end;
  finally
    lRegistry.Free;
  end;
end;

class function TTortoiseGit.BuildParameters(const aCommand: TTortoiseGitCommand;
  const aRepoRoot: string): string;
var
  lCommandName: string;
begin
  case aCommand of
    TTortoiseGitCommand.tgcCommit: lCommandName := 'commit';
    TTortoiseGitCommand.tgcSync: lCommandName := 'sync';
  else
    lCommandName := '';
  end;
  Result := Format('/command:%s /path:"%s"', [lCommandName, aRepoRoot]);
end;

class function TTortoiseGit.ResolveExecutable(const aCandidates: TArray<string>;
  const aPathValue: string): string;
var
  lCandidate: string;
  lCandidateExe: string;
  lPathPart: string;
begin
  Result := '';
  for lCandidate in aCandidates do
  begin
    lCandidateExe := Trim(lCandidate).Trim(['"']);
    if FileExists(lCandidateExe) then
      Exit(TPath.GetFullPath(lCandidateExe));
    if DirectoryExists(lCandidateExe) then
    begin
      lCandidateExe := TPath.Combine(lCandidateExe, 'bin\TortoiseGitProc.exe');
      if FileExists(lCandidateExe) then
        Exit(TPath.GetFullPath(lCandidateExe));
    end;
  end;

  for lPathPart in aPathValue.Split([';']) do
  begin
    lCandidateExe := Trim(lPathPart).Trim(['"']);
    if lCandidateExe = '' then
      Continue;
    lCandidateExe := TPath.Combine(lCandidateExe, 'TortoiseGitProc.exe');
    if FileExists(lCandidateExe) then
      Exit(TPath.GetFullPath(lCandidateExe));
  end;
end;

class function TTortoiseGit.DetectExecutable: string;
var
  lCandidates: TArray<string>;
  lRoot: string;
begin
  lCandidates := [];
  AddRegistryCandidates(lCandidates);
  lRoot := GetEnvironmentVariable('ProgramW6432');
  if lRoot <> '' then
    AddCandidate(lCandidates, TPath.Combine(lRoot, 'TortoiseGit'));
  lRoot := GetEnvironmentVariable('ProgramFiles');
  if lRoot <> '' then
    AddCandidate(lCandidates, TPath.Combine(lRoot, 'TortoiseGit'));
  lRoot := GetEnvironmentVariable('ProgramFiles(x86)');
  if lRoot <> '' then
    AddCandidate(lCandidates, TPath.Combine(lRoot, 'TortoiseGit'));
  Result := ResolveExecutable(lCandidates, GetEnvironmentVariable('PATH'));
end;

class function TTortoiseGit.TryLaunch(const aExecutable: string; const aCommand: TTortoiseGitCommand;
  const aRepoRoot: string; out aError: string): Boolean;
var
  lCode: NativeInt;
  lParameters: string;
begin
  aError := '';
  if not FileExists(aExecutable) then
  begin
    aError := Format(rsLaunchFailed, [ERROR_FILE_NOT_FOUND]);
    Exit(False);
  end;

  lParameters := BuildParameters(aCommand, aRepoRoot);
  lCode := NativeInt(ShellExecute(0, 'open', PChar(aExecutable), PChar(lParameters),
    PChar(aRepoRoot), SW_SHOWNORMAL));
  Result := lCode > 32;
  if not Result then
    aError := Format(rsLaunchFailed, [lCode]);
end;

end.
