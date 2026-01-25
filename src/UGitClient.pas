unit UGitClient;

interface

uses
  System.Classes, System.Diagnostics, System.Generics.Collections, System.IOUtils,
  System.StrUtils, System.SysUtils,

  Winapi.Windows,

  AutoFree, maxLogic.ioutils, maxLogic.StrUtils,
  UModels;

resourcestring
  rsBranchDetached = '(detached)';
  rsBranchUnknown = '(unknown)';
  rsSummaryMore = ' ...(+ %d)';
  rsDirtyStaged = 'Staged';
  rsDirtyUnstaged = 'Unstaged';
  rsDirtyUntracked = 'Untracked';
  rsDirtyMixed = 'Mixed';

type
  TWriteAccessInfo = record
    Exists: Boolean;
    Writable: Boolean;
    ReadOnly: Boolean;
    Error: string;
  end;

  TGitWriteDiagnostics = record
    GitMarkerPath: string;
    GitMarkerIsFile: Boolean;
    GitDirPath: string;
    GitDirInfo: TWriteAccessInfo;
    ModulesPath: string;
    ModulesInfo: TWriteAccessInfo;
  end;

  TGitStatusParse = record
    HasStaged: Boolean;
    HasUnstaged: Boolean;
    HasUntracked: Boolean;
    Summary: string;
  end;

  TGitClient = class
  private
    function BuildCommandLine(const aExe: string; const aArgs: TArray<string>): string;
    function QuoteArg(const aArg: string): string;
    function TryReadAvailableFromPipe(const aPipe: THandle; out aBytes: TBytes; out aDidRead: Boolean; out aError: string): Boolean;
    function TryRunProcess(const aCommandLine: string; const aWorkDir: string;
      const aTimeoutMs: Cardinal; out aExitCode: Cardinal; out aOutput: TBytes; out aError: string): Boolean;
    function GetWriteAccessInfo(const aPath: string): TWriteAccessInfo;
    function ShouldRetryFetch(const aOutput: string): Boolean;
  public
    function TryRunGit(const aRepo: string; const aArgs: TArray<string>; out aResult: TGitResult;
      out aError: string; const aTimeoutMs: Cardinal = 0): Boolean;
    function TryGetRepoRoot(const aPath: string; out aRepoRoot: string; out aError: string): Boolean;
    function TryIsInsideWorkTree(const aRepoRoot: string; out aIsInside: Boolean; out aError: string): Boolean;
    function TryGetBranch(const aRepoRoot: string; out aBranch: string; out aError: string): Boolean;
    function TryGetUpstream(const aRepoRoot: string; out aUpstream: string; out aError: string): Boolean;
    function TryGetRemoteUrl(const aRepoRoot: string; const aRemote: string; out aRemoteUrl: string;
      out aError: string): Boolean;
    function TryGetOriginUrl(const aRepoRoot: string; out aOriginUrl: string; out aError: string): Boolean;
    function TryFetchRemote(const aRepoRoot: string; const aRemote: string; const aTimeoutMs: Cardinal;
      out aError: string): Boolean;
    function TryFetchOrigin(const aRepoRoot: string; const aTimeoutMs: Cardinal; out aError: string): Boolean;
    function TryGetStatusPorcelain(const aRepoRoot: string; out aLines: TArray<string>; out aError: string): Boolean;
    function TryGetAheadBehind(const aRepoRoot: string; const aUpstream: string; out aAhead: Integer;
      out aBehind: Integer; out aError: string): Boolean;
    function TryGetGitWriteDiagnostics(const aRepoRoot: string; out aDiag: TGitWriteDiagnostics;
      out aError: string): Boolean;
    function TryPull(const aRepoRoot: string; out aError: string): Boolean;
    function TryPush(const aRepoRoot: string; out aError: string): Boolean;
    function TryCommit(const aRepoRoot: string; const aMessage: string; out aError: string): Boolean;
    class function ParseStatusPorcelain(const aLines: TArray<string>): TGitStatusParse; static;
    class function ParseAheadBehind(const aLine: string; out aAhead: Integer; out aBehind: Integer): Boolean; static;
  end;

implementation

const
  cGitExe = 'git';
  cDefaultNetworkTimeoutMs = 60000;
  cDefaultGitTimeoutMs = 20000;

type
  TEnvOverride = record
    Name: string;
    Value: string;
    class function Create(const aName: string; const aValue: string): TEnvOverride; static;
  end;

function BuildEnvBlock(const aOverrides: array of TEnvOverride): string;
var
  g: TGarbos;
  lEnv: PWideChar;
  lP: PWideChar;
  lEq: PWideChar;
  lName: string;
  lValue: string;
  lDict: TDictionary<string, string>;
  lExtra: TList<string>;
  lPair: TPair<string, string>;
  lLine: string;
  i: Integer;
begin
  Result := '';

  GC(lDict, TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase), g);
  GC(lExtra, TList<string>.Create, g);

  lEnv := GetEnvironmentStringsW;
  if lEnv <> nil then
  begin
    try
      lP := lEnv;
      while lP^ <> #0 do
      begin
        lLine := lP;
        lEq := StrScan(lP, '=');
        if lEq = lP then
        begin
          lExtra.Add(lLine);
        end else if lEq <> nil then
        begin
          SetString(lName, lP, lEq - lP);
          lValue := lEq + 1;
          lDict.AddOrSetValue(lName, lValue);
        end;
        Inc(lP, lstrlenW(lP) + 1);
      end;
    finally
      FreeEnvironmentStringsW(lEnv);
    end;
  end;

  for i := 0 to High(aOverrides) do
    lDict.AddOrSetValue(aOverrides[i].Name, aOverrides[i].Value);

  for lLine in lExtra do
    Result := Result + lLine + #0;
  for lPair in lDict do
    Result := Result + lPair.Key + '=' + lPair.Value + #0;

  Result := Result + #0;
  UniqueString(Result);
end;

class function TEnvOverride.Create(const aName: string; const aValue: string): TEnvOverride;
begin
  Result.Name := aName;
  Result.Value := aValue;
end;

function OpenNullInputHandle(out aError: string): THandle;
begin
  aError := '';
  Result := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL, 0);
  if Result = INVALID_HANDLE_VALUE then
  begin
    aError := SysErrorMessage(GetLastError);
    Result := 0;
  end;
end;

function TGitClient.BuildCommandLine(const aExe: string; const aArgs: TArray<string>): string;
var
  g: TGarbos;
  i: Integer;
  lParts: TStringBuilder;
begin
  GC(lParts, TStringBuilder.Create, g);
  lParts.Append(QuoteArg(aExe));
  for i := 0 to Length(aArgs) - 1 do
  begin
    lParts.Append(' ');
    lParts.Append(QuoteArg(aArgs[i]));
  end;
  Result := lParts.ToString;
end;

function TGitClient.QuoteArg(const aArg: string): string;
var
  lNeedsQuote: Boolean;
  lValue: string;
  lBackslashCount: Integer;
  i: Integer;
  lChar: Char;
begin
  lValue := aArg;
  if lValue = '' then
    Exit('""');

  lNeedsQuote := lValue.Contains(' ') or lValue.Contains(#9) or lValue.Contains('"');
  if not lNeedsQuote then
    Exit(lValue);

  Result := '"';
  lBackslashCount := 0;
  for i := 1 to Length(lValue) do
  begin
    lChar := lValue[i];
    if lChar = '\' then
    begin
      Inc(lBackslashCount);
      Continue;
    end;

    if lChar = '"' then
    begin
      Result := Result + StringOfChar('\', lBackslashCount * 2 + 1) + '"';
      lBackslashCount := 0;
      Continue;
    end;

    if lBackslashCount > 0 then
    begin
      Result := Result + StringOfChar('\', lBackslashCount);
      lBackslashCount := 0;
    end;
    Result := Result + lChar;
  end;

  if lBackslashCount > 0 then
    Result := Result + StringOfChar('\', lBackslashCount * 2);
  Result := Result + '"';
end;

function TGitClient.TryReadAvailableFromPipe(const aPipe: THandle; out aBytes: TBytes; out aDidRead: Boolean; out aError: string): Boolean;
var
  lBuffer: array[0..4095] of Byte;
  lRead: Cardinal;
  lAvail: Cardinal;
begin
  aError := '';
  aDidRead := False;
  aBytes := [];
  Result := True;

  lAvail := 0;
  if not PeekNamedPipe(aPipe, nil, 0, nil, @lAvail, nil) then
  begin
    aError := SysErrorMessage(GetLastError);
    Exit(False);
  end;
  if lAvail = 0 then
    Exit(True);

  lRead := 0;
  if not ReadFile(aPipe, lBuffer, SizeOf(lBuffer), lRead, nil) then
  begin
    if GetLastError = ERROR_BROKEN_PIPE then
      Exit(True);
    aError := SysErrorMessage(GetLastError);
    Exit(False);
  end;
  if lRead = 0 then
    Exit(True);

  SetLength(aBytes, lRead);
  Move(lBuffer[0], aBytes[0], lRead);
  aDidRead := True;
end;

function TGitClient.TryRunProcess(const aCommandLine: string; const aWorkDir: string;
  const aTimeoutMs: Cardinal; out aExitCode: Cardinal; out aOutput: TBytes; out aError: string): Boolean;
var
  lSecAttr: TSecurityAttributes;
  lRead: THandle;
  lWrite: THandle;
  lStartInfo: TStartupInfoW;
  lProcInfo: TProcessInformation;
  lWait: Cardinal;
  lSw: TStopwatch;
  lTimedOut: Boolean;
  lExit: Cardinal;
  lCmd: string;
  lPipeError: string;
  lDidRead: Boolean;
  lChunk: TBytes;
  lOut: TBytesStream;
  lNullIn: THandle;
  lNullErr: string;
  lEnvBlock: string;
  lEnvPtr: Pointer;
  lEffectiveTimeout: Cardinal;
  g: TGarbos;
begin
  Result := False;
  aError := '';
  aExitCode := 0;
  aOutput := [];

  if aTimeoutMs > 0 then
    lEffectiveTimeout := aTimeoutMs
  else
    lEffectiveTimeout := cDefaultGitTimeoutMs;

  GC(lOut, TBytesStream.Create, g);

  lSecAttr.nLength := SizeOf(lSecAttr);
  lSecAttr.lpSecurityDescriptor := nil;
  lSecAttr.bInheritHandle := True;

  if not CreatePipe(lRead, lWrite, @lSecAttr, 0) then
  begin
    aError := SysErrorMessage(GetLastError);
    Exit(False);
  end;

  SetHandleInformation(lRead, HANDLE_FLAG_INHERIT, 0);

  lNullIn := OpenNullInputHandle(lNullErr);
  if lNullIn = 0 then
  begin
    CloseHandle(lWrite);
    CloseHandle(lRead);
    aError := lNullErr;
    Exit(False);
  end;

  ZeroMemory(@lStartInfo, SizeOf(lStartInfo));
  lStartInfo.cb := SizeOf(lStartInfo);
  lStartInfo.dwFlags := STARTF_USESTDHANDLES;
  lStartInfo.hStdOutput := lWrite;
  lStartInfo.hStdError := lWrite;
  lStartInfo.hStdInput := lNullIn;

  ZeroMemory(@lProcInfo, SizeOf(lProcInfo));
  lCmd := aCommandLine;
  UniqueString(lCmd);

  lEnvBlock := BuildEnvBlock([
    TEnvOverride.Create('GIT_TERMINAL_PROMPT', '0'),
    TEnvOverride.Create('GCM_INTERACTIVE', 'Never'),
    TEnvOverride.Create('GIT_OPTIONAL_LOCKS', '0')
  ]);
  lEnvPtr := PWideChar(lEnvBlock);

  if not CreateProcessW(nil, PWideChar(lCmd), nil, nil, True, CREATE_NO_WINDOW or CREATE_UNICODE_ENVIRONMENT,
    lEnvPtr, PWideChar(aWorkDir), lStartInfo, lProcInfo) then
  begin
    aError := SysErrorMessage(GetLastError);
    CloseHandle(lNullIn);
    CloseHandle(lWrite);
    CloseHandle(lRead);
    Exit(False);
  end;

  CloseHandle(lWrite);
  CloseHandle(lNullIn);

  lTimedOut := False;
  lSw := TStopwatch.StartNew;

  repeat
    repeat
      if not TryReadAvailableFromPipe(lRead, lChunk, lDidRead, lPipeError) then
      begin
        aError := lPipeError;
        Break;
      end;
      if lDidRead and (Length(lChunk) > 0) then
        lOut.WriteBuffer(lChunk[0], Length(lChunk));
    until not lDidRead;

    if aError <> '' then
      Break;

    lWait := WaitForSingleObject(lProcInfo.hProcess, 50);
    if (lEffectiveTimeout > 0) and (lSw.ElapsedMilliseconds > lEffectiveTimeout) then
    begin
      TerminateProcess(lProcInfo.hProcess, 1);
      lTimedOut := True;
      Break;
    end;
  until lWait <> WAIT_TIMEOUT;

  repeat
    if not TryReadAvailableFromPipe(lRead, lChunk, lDidRead, lPipeError) then
    begin
      if aError = '' then
        aError := lPipeError
      else begin
        if lPipeError <> '' then
          aError := aError + ' | ' + lPipeError;
      end;
      Break;
    end;
    if lDidRead and (Length(lChunk) > 0) then
      lOut.WriteBuffer(lChunk[0], Length(lChunk));
  until not lDidRead;

  if GetExitCodeProcess(lProcInfo.hProcess, lExit) then
    aExitCode := lExit;

  CloseHandle(lProcInfo.hProcess);
  CloseHandle(lProcInfo.hThread);
  CloseHandle(lRead);

  if lTimedOut then
  begin
    if aError <> '' then
      aError := aError + ' | process timeout'
    else
      aError := 'process timeout';
  end;

  aOutput := lOut.Bytes;
  SetLength(aOutput, lOut.Size);

  Result := not lTimedOut;
end;

function TGitClient.TryRunGit(const aRepo: string; const aArgs: TArray<string>; out aResult: TGitResult;
  out aError: string; const aTimeoutMs: Cardinal): Boolean;
var
  lCmd: string;
  lBytes: TBytes;
  lText: string;
  lExit: Cardinal;
begin
  aResult := Default(TGitResult);
  aError := '';

  lCmd := BuildCommandLine(cGitExe, aArgs);
  if not TryRunProcess(lCmd, aRepo, aTimeoutMs, lExit, lBytes, aError) then
    Exit(False);

  aResult.ExitCode := lExit;
  if Length(lBytes) > 0 then
  begin
    try
      lText := TEncoding.UTF8.GetString(lBytes);
    except
      lText := TEncoding.Default.GetString(lBytes);
    end;
  end else begin
    lText := '';
  end;

  aResult.OutputText := lText;
  if lText <> '' then
    aResult.OutputLines := lText.Replace(#13, '').Split([#10])
  else
    aResult.OutputLines := [];

  Result := True;
end;

function TGitClient.TryGetRepoRoot(const aPath: string; out aRepoRoot: string; out aError: string): Boolean;
var
  lRes: TGitResult;
  lErr: string;
begin
  aRepoRoot := '';
  aError := '';

  if not TryRunGit(aPath, ['rev-parse', '--show-toplevel'], lRes, lErr, 0) then
  begin
    aError := lErr;
    Exit(False);
  end;

  if lRes.ExitCode <> 0 then
  begin
    aError := lRes.OutputText.Trim;
    Exit(False);
  end;

  if Length(lRes.OutputLines) > 0 then
    aRepoRoot := lRes.OutputLines[0].Trim;
  Result := aRepoRoot <> '';
  if not Result then
    aError := 'empty repo root';
end;

function TGitClient.TryIsInsideWorkTree(const aRepoRoot: string; out aIsInside: Boolean; out aError: string): Boolean;
var
  lRes: TGitResult;
  lErr: string;
begin
  aIsInside := False;
  if not TryRunGit(aRepoRoot, ['rev-parse', '--is-inside-work-tree'], lRes, lErr, 0) then
  begin
    aError := lErr;
    Exit(False);
  end;
  if lRes.ExitCode <> 0 then
  begin
    aError := lRes.OutputText.Trim;
    Exit(False);
  end;
  if Length(lRes.OutputLines) > 0 then
    aIsInside := SameText(lRes.OutputLines[0].Trim, 'true');
  Result := True;
end;

function TGitClient.TryGetBranch(const aRepoRoot: string; out aBranch: string; out aError: string): Boolean;
var
  lRes: TGitResult;
  lErr: string;
begin
  aBranch := rsBranchUnknown;
  if not TryRunGit(aRepoRoot, ['rev-parse', '--abbrev-ref', 'HEAD'], lRes, lErr, 0) then
  begin
    aError := lErr;
    Exit(False);
  end;
  if lRes.ExitCode = 0 then
  begin
    if Length(lRes.OutputLines) > 0 then
      aBranch := lRes.OutputLines[0].Trim;
  end;
  if SameText(aBranch, 'HEAD') then
    aBranch := rsBranchDetached;
  Result := True;
end;

function TGitClient.TryGetUpstream(const aRepoRoot: string; out aUpstream: string; out aError: string): Boolean;
var
  lRes: TGitResult;
  lErr: string;
begin
  aUpstream := '';
  if not TryRunGit(aRepoRoot, ['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'], lRes, lErr, 0) then
  begin
    aError := lErr;
    Exit(False);
  end;
  if lRes.ExitCode = 0 then
  begin
    if Length(lRes.OutputLines) > 0 then
      aUpstream := lRes.OutputLines[0].Trim;
  end;
  Result := True;
end;

function TGitClient.TryGetRemoteUrl(const aRepoRoot: string; const aRemote: string; out aRemoteUrl: string;
  out aError: string): Boolean;
var
  lRes: TGitResult;
  lErr: string;
begin
  aRemoteUrl := '';
  aError := '';
  if aRemote.Trim = '' then
  begin
    aError := 'remote name is required';
    Exit(False);
  end;

  if not TryRunGit(aRepoRoot, ['remote', 'get-url', aRemote], lRes, lErr, 0) then
  begin
    aError := lErr;
    Exit(False);
  end;
  if lRes.ExitCode = 0 then
  begin
    if Length(lRes.OutputLines) > 0 then
      aRemoteUrl := lRes.OutputLines[0].Trim;
  end;
  Result := True;
end;

function TGitClient.TryGetOriginUrl(const aRepoRoot: string; out aOriginUrl: string; out aError: string): Boolean;
begin
  Result := TryGetRemoteUrl(aRepoRoot, 'origin', aOriginUrl, aError);
end;

function TGitClient.TryFetchRemote(const aRepoRoot: string; const aRemote: string; const aTimeoutMs: Cardinal;
  out aError: string): Boolean;
var
  lRes: TGitResult;
  lErr: string;
  lRetry: Boolean;
begin
  aError := '';
  if aRemote.Trim = '' then
  begin
    aError := 'remote name is required';
    Exit(False);
  end;
  if not TryRunGit(aRepoRoot, ['fetch', '--prune', aRemote], lRes, lErr, aTimeoutMs) then
  begin
    aError := lErr;
    Exit(False);
  end;
  if lRes.ExitCode = 0 then
    Exit(True);

  aError := lRes.OutputText.Trim;
  lRetry := ShouldRetryFetch(lRes.OutputText);
  if lRetry then
  begin
    Sleep(3000);
    if not TryRunGit(aRepoRoot, ['fetch', '--prune', aRemote], lRes, lErr, aTimeoutMs) then
    begin
      aError := lErr;
      Exit(False);
    end;
    if lRes.ExitCode = 0 then
      Exit(True);
    aError := aError + ' | retry: ' + lRes.OutputText.Trim;
  end;
  Result := False;
end;

function TGitClient.TryFetchOrigin(const aRepoRoot: string; const aTimeoutMs: Cardinal; out aError: string): Boolean;
begin
  Result := TryFetchRemote(aRepoRoot, 'origin', aTimeoutMs, aError);
end;

function TGitClient.TryGetStatusPorcelain(const aRepoRoot: string; out aLines: TArray<string>; out aError: string): Boolean;
var
  lRes: TGitResult;
  lErr: string;
  lList: TList<string>;
  g: TGarbos;
  lTokens: TArray<string>;
  lIndex: Integer;
  lToken: string;
  lLine: string;
  lPath: string;
  lX: Char;
  lY: Char;
begin
  aError := '';
  aLines := [];

  if not TryRunGit(aRepoRoot, ['status', '--porcelain', '-z'], lRes, lErr, 0) then
  begin
    aError := lErr;
    Exit(False);
  end;

  if lRes.ExitCode <> 0 then
  begin
    aError := lRes.OutputText.Trim;
    Exit(False);
  end;

  GC(lList, TList<string>.Create, g);
  if lRes.OutputText <> '' then
  begin
    lTokens := lRes.OutputText.Split([#0], TStringSplitOptions.ExcludeEmpty);
    lIndex := 0;
    while lIndex < Length(lTokens) do
    begin
      lToken := lTokens[lIndex];
      if (Length(lToken) < 3) or (lToken[3] <> ' ') then
      begin
        Inc(lIndex);
        Continue;
      end;

      lX := lToken[1];
      lY := lToken[2];
      lPath := lToken.Substring(3);

      if ((lX = 'R') or (lX = 'C') or (lY = 'R') or (lY = 'C')) and (lIndex + 1 < Length(lTokens)) then
      begin
        lPath := lTokens[lIndex + 1];
        Inc(lIndex);
      end;

      lLine := lToken.Substring(0, 3) + lPath;
      if lLine.Trim <> '' then
        lList.Add(lLine);
      Inc(lIndex);
    end;
  end;

  aLines := lList.ToArray;
  Result := True;
end;

function TGitClient.TryGetAheadBehind(const aRepoRoot: string; const aUpstream: string; out aAhead: Integer;
  out aBehind: Integer; out aError: string): Boolean;
var
  lRes: TGitResult;
  lErr: string;
  lLine: string;
begin
  aAhead := 0;
  aBehind := 0;
  aError := '';

  if not TryRunGit(aRepoRoot, ['rev-list', '--left-right', '--count', 'HEAD...' + aUpstream], lRes, lErr, 0) then
  begin
    aError := lErr;
    Exit(False);
  end;

  if lRes.ExitCode <> 0 then
  begin
    aError := lRes.OutputText.Trim;
    Exit(False);
  end;

  lLine := '';
  if Length(lRes.OutputLines) > 0 then
    lLine := lRes.OutputLines[0].Trim;

  Result := ParseAheadBehind(lLine, aAhead, aBehind);
  if not Result then
    aError := 'failed to parse ahead/behind';
end;

function TGitClient.GetWriteAccessInfo(const aPath: string): TWriteAccessInfo;
var
  g: TGarbos;
  lAttr: Cardinal;
  lTmp: string;
  lDir: string;
  lStream: TFileStream;
  lPath: string;
begin
  Result := Default(TWriteAccessInfo);
  if aPath = '' then
  begin
    Result.Error := 'no path';
    Exit;
  end;

  lPath := NormalizePath(aPath);
  if not FileExists(lPath) and not DirectoryExists(lPath) then
  begin
    Result.Exists := False;
    Result.Error := 'missing';
    Exit;
  end;

  Result.Exists := True;
  lAttr := GetFileAttributes(PChar(lPath));
  if lAttr = INVALID_FILE_ATTRIBUTES then
  begin
    Result.Error := SysErrorMessage(GetLastError);
    Result.Writable := False;
    Exit;
  end;
  Result.ReadOnly := (lAttr and FILE_ATTRIBUTE_READONLY) <> 0;

  if Result.ReadOnly then
    Exit;

  try
    if DirectoryExists(lPath) then
      lDir := lPath
    else
      lDir := ExtractFilePath(lPath);
    lTmp := TPath.Combine(lDir, '.permcheck_' + TGuid.NewGuid.ToString);
    GC(lStream, TFileStream.Create(lTmp, fmCreate or fmShareExclusive), g);
    Result.Writable := True;
    g.Clear; // we release the handle before cleanup to avoid self-locking
    if FileExists(lTmp) then
      TFile.Delete(lTmp);
  except
    on E: Exception do
    begin
      Result.Error := E.Message;
      Result.Writable := False;
    end;
  end;
end;

function TGitClient.TryGetGitWriteDiagnostics(const aRepoRoot: string; out aDiag: TGitWriteDiagnostics;
  out aError: string): Boolean;
var
  lGitMarkerPath: string;
  lGitDirPath: string;
  lLine: string;
  lResolved: string;
  lModulesPath: string;
  lModulesRoot: string;
  lNorm: string;
  lTokenPos: Integer;
  lToken: string;
  lRel: string;
  g: TGarbos;
  lLines: TStringList;
begin
  aError := '';
  aDiag := Default(TGitWriteDiagnostics);

  lGitMarkerPath := TPath.Combine(aRepoRoot, '.git');
  aDiag.GitMarkerPath := lGitMarkerPath;

  if DirectoryExists(lGitMarkerPath) then
  begin
    aDiag.GitDirPath := lGitMarkerPath;
  end else if FileExists(lGitMarkerPath) then
  begin
    aDiag.GitMarkerIsFile := True;
    GC(lLines, TStringList.Create, g);
    try
      lLines.LoadFromFile(lGitMarkerPath, TEncoding.UTF8);
      if lLines.Count > 0 then
      begin
        lLine := lLines[0];
        if StartsText('gitdir:', lLine.Trim) then
        begin
          lRel := lLine.Trim.Substring(7).Trim;
          lResolved := TPath.Combine(aRepoRoot, lRel);
          lResolved := TPath.GetFullPath(lResolved);
          lGitDirPath := lResolved;
        end;
      end;
    except
      lGitDirPath := '';
    end;
    aDiag.GitDirPath := lGitDirPath;
  end;

  if aDiag.GitDirPath <> '' then
    aDiag.GitDirInfo := GetWriteAccessInfo(aDiag.GitDirPath);

  lModulesPath := CombinePath([aRepoRoot, '.git', 'modules']);
  lModulesRoot := '';
  if aDiag.GitDirPath <> '' then
  begin
    lNorm := aDiag.GitDirPath.Replace('/', '\');
    lToken := '\.git\modules\';
    lTokenPos := lNorm.ToLowerInvariant.IndexOf(lToken);
    if lTokenPos >= 0 then
      lModulesRoot := lNorm.Substring(0, lTokenPos + lToken.Length - 1).TrimRight(['\']);
  end;

  if DirectoryExists(lModulesPath) then
    aDiag.ModulesPath := lModulesPath
  else if (lModulesRoot <> '') and DirectoryExists(lModulesRoot) then
    aDiag.ModulesPath := lModulesRoot;

  if aDiag.ModulesPath <> '' then
    aDiag.ModulesInfo := GetWriteAccessInfo(aDiag.ModulesPath);

  Result := True;
end;

function TGitClient.ShouldRetryFetch(const aOutput: string): Boolean;
var
  lText: string;
begin
  lText := aOutput.ToLowerInvariant;
  Result := (lText.Contains('failed to connect')) or
    (lText.Contains('could not resolve host')) or
    (lText.Contains('connection timed out')) or
    (lText.Contains('timed out')) or
    (lText.Contains('connection reset')) or
    (lText.Contains('proxy')) or
    (lText.Contains('rate limit')) or
    (lText.Contains('error: 429')) or
    (lText.Contains('temporary failure')) or
    (lText.Contains('recv failure')) or
    (lText.Contains('schannel')) or
    (lText.Contains('gnutls')) or
    (lText.Contains('ssl'));
end;

function TGitClient.TryPull(const aRepoRoot: string; out aError: string): Boolean;
var
  lRes: TGitResult;
  lErr: string;
begin
  aError := '';
  if not TryRunGit(aRepoRoot, ['pull', '--ff-only'], lRes, lErr, cDefaultNetworkTimeoutMs) then
  begin
    aError := lErr;
    Exit(False);
  end;
  Result := lRes.ExitCode = 0;
  if not Result then
    aError := lRes.OutputText.Trim;
end;

function TGitClient.TryPush(const aRepoRoot: string; out aError: string): Boolean;
var
  lRes: TGitResult;
  lErr: string;
begin
  aError := '';
  if not TryRunGit(aRepoRoot, ['push'], lRes, lErr, cDefaultNetworkTimeoutMs) then
  begin
    aError := lErr;
    Exit(False);
  end;
  Result := lRes.ExitCode = 0;
  if not Result then
    aError := lRes.OutputText.Trim;
end;

function TGitClient.TryCommit(const aRepoRoot: string; const aMessage: string; out aError: string): Boolean;
var
  lStatusLines: TArray<string>;
  lParse: TGitStatusParse;
  lRes: TGitResult;
  lErr: string;
begin
  aError := '';

  if aMessage.Trim = '' then
  begin
    aError := 'commit message is required';
    Exit(False);
  end;

  if not TryGetStatusPorcelain(aRepoRoot, lStatusLines, lErr) then
  begin
    aError := lErr;
    Exit(False);
  end;

  lParse := ParseStatusPorcelain(lStatusLines);
  if (not lParse.HasStaged) and (not lParse.HasUnstaged) and (not lParse.HasUntracked) then
  begin
    aError := 'nothing to commit';
    Exit(False);
  end;

  if not lParse.HasStaged then
  begin
    if not TryRunGit(aRepoRoot, ['add', '-A'], lRes, lErr, 0) then
    begin
      aError := lErr;
      Exit(False);
    end;
    if lRes.ExitCode <> 0 then
    begin
      aError := lRes.OutputText.Trim;
      Exit(False);
    end;
  end;

  if not TryRunGit(aRepoRoot, ['commit', '-m', aMessage], lRes, lErr, 0) then
  begin
    aError := lErr;
    Exit(False);
  end;
  Result := lRes.ExitCode = 0;
  if not Result then
    aError := lRes.OutputText.Trim;
end;

class function TGitClient.ParseStatusPorcelain(const aLines: TArray<string>): TGitStatusParse;
var
  lLine: string;
  x: Char;
  y: Char;
  g: TGarbos;
  lPath: string;
  lName: string;
  lFilePath: string;
  lSummary: string;
  lArrowPos: Integer;
  lFiles: TStringList;
  lItems: TArray<string>;
  i: Integer;
begin
  Result := Default(TGitStatusParse);
  if Length(aLines) = 0 then
    Exit;

  GC(lFiles, TStringList.Create, g);
  lFiles.Sorted := True;
  lFiles.Duplicates := dupIgnore;

  for lLine in aLines do
  begin
    if lLine.Trim = '' then
      Continue;
    if Length(lLine) < 2 then
      Continue;

    x := lLine[1];
    y := lLine[2];

    if (x <> ' ') and (x <> '?') then
      Result.HasStaged := True;
    if (y <> ' ') and (y <> '?') then
      Result.HasUnstaged := True;
    if (x = '?') and (y = '?') then
      Result.HasUntracked := True;

    if Length(lLine) >= 4 then
      lPath := lLine.Substring(3).Trim
    else
      lPath := lLine.Trim;
    if lPath = '' then
      Continue;

    lArrowPos := lPath.LastIndexOf(' -> ');
    if lArrowPos >= 0 then
      lPath := lPath.Substring(lArrowPos + 4).Trim;
    if (Length(lPath) >= 2) and (lPath[1] = '"') and (lPath[Length(lPath)] = '"') then
      lPath := AnsiDequotedStr(lPath, '"');
    lFilePath := lPath.Replace('/', '\');
    lName := ExtractFileName(lFilePath);
    if lName <> '' then
    begin
      if lFiles.IndexOf(lName) < 0 then
        lFiles.Add(lName);
    end;
  end;

  lSummary := '';
  if lFiles.Count > 0 then
  begin
    SetLength(lItems, lFiles.Count);
    for i := 0 to lFiles.Count - 1 do
      lItems[i] := lFiles[i];
    lSummary := String.Join(', ', lItems);
  end else if Result.HasStaged and (not Result.HasUnstaged) and (not Result.HasUntracked) then
  begin
    lSummary := rsDirtyStaged;
  end else if Result.HasUntracked and (not Result.HasStaged) and (not Result.HasUnstaged) then
  begin
    lSummary := rsDirtyUntracked;
  end else if Result.HasUnstaged and (not Result.HasStaged) and (not Result.HasUntracked) then
  begin
    lSummary := rsDirtyUnstaged;
  end else if Result.HasStaged or Result.HasUnstaged or Result.HasUntracked then
  begin
    lSummary := rsDirtyMixed;
  end;

  Result.Summary := lSummary;
end;

class function TGitClient.ParseAheadBehind(const aLine: string; out aAhead: Integer; out aBehind: Integer): Boolean;
var
  lParts: TArray<string>;
begin
  aAhead := 0;
  aBehind := 0;
  lParts := aLine.Trim.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  if Length(lParts) < 2 then
    Exit(False);
  if not TryStrToInt(lParts[0], aAhead) then
    Exit(False);
  if not TryStrToInt(lParts[1], aBehind) then
    Exit(False);
  Result := True;
end;

end.
