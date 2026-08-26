unit UUiEventQueue;

interface

uses
  System.Diagnostics, System.Generics.Collections, System.SyncObjs,
  UModels;

{$SCOPEDENUMS ON}

type
  TUiEventKind = (uekLog, uekProgressStart, uekProgressUpdate, uekProgressEnd,
    uekRepoWaiting, uekRepoResult, uekScanFinished, uekActionResult, uekClearResults);

  TUiEvent = record
    Kind: TUiEventKind;
    Generation: Int64;
    Text: string;
    ProgressMode: TProgressMode;
    ProgressMax: Integer;
    ProgressValue: Integer;
    RepoRoot: string;
    RepoStatus: TRepoStatus;
    RelatedRepoStatus: TRepoStatus;
    ActionTag: Integer;
    ActionSucceeded: Boolean;
    ActionError: string;
    AlertText: string;
  end;

  TUiEventHandler = reference to procedure(const aEvent: TUiEvent);
  TUiClock = reference to function: Int64;

  TUiEventPumpResult = record
    DequeuedCount: Integer;
    DeliveredCount: Integer;
    HasMore: Boolean;
    ElapsedMilliseconds: Int64;
  end;

  TUiEventQueue = class
  private
    fQueue: TList<TUiEvent>;
    fLock: TCriticalSection;
    fHead: Integer;
    fLogicalCount: Integer;
    fPeakCount: Integer;
    fPendingProgressIndex: TDictionary<Int64, Integer>;
    fSuperseded: TDictionary<Integer, Boolean>;
    procedure Compact;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Enqueue(const aEvent: TUiEvent);
    function TryDequeue(out aEvent: TUiEvent): Boolean;
    function Count: Integer;
    function PeakCount: Integer;
    procedure ResetPeakCount;
    procedure Clear;
  end;

  TUiEventPump = class
  public
    class function Process(const aQueue: TUiEventQueue; const aActiveGeneration: Int64;
      const aMaxEvents: Integer; const aMaxMilliseconds: Int64;
      const aHandler: TUiEventHandler; const aClock: TUiClock = nil): TUiEventPumpResult; static;
  end;

implementation

constructor TUiEventQueue.Create;
begin
  inherited Create;
  fQueue := TList<TUiEvent>.Create;
  fLock := TCriticalSection.Create;
  fPendingProgressIndex := TDictionary<Int64, Integer>.Create;
  fSuperseded := TDictionary<Integer, Boolean>.Create;
end;

procedure TUiEventQueue.Clear;
begin
  fLock.Enter;
  try
    fQueue.Clear;
    fPendingProgressIndex.Clear;
    fSuperseded.Clear;
    fHead := 0;
    fLogicalCount := 0;
    fPeakCount := 0;
  finally
    fLock.Leave;
  end;
end;

destructor TUiEventQueue.Destroy;
begin
  fSuperseded.Free;
  fPendingProgressIndex.Free;
  fLock.Free;
  fQueue.Free;
  inherited;
end;

procedure TUiEventQueue.Enqueue(const aEvent: TUiEvent);
var
  lIndex: Integer;
  lPreviousIndex: Integer;
begin
  fLock.Enter;
  try
    lIndex := fQueue.Add(aEvent);
    if aEvent.Kind = TUiEventKind.uekProgressUpdate then
    begin
      if fPendingProgressIndex.TryGetValue(aEvent.Generation, lPreviousIndex) then
        fSuperseded.AddOrSetValue(lPreviousIndex, True)
      else
        Inc(fLogicalCount);
      fPendingProgressIndex.AddOrSetValue(aEvent.Generation, lIndex);
    end else begin
      Inc(fLogicalCount);
    end;
    if fLogicalCount > fPeakCount then
      fPeakCount := fLogicalCount;
  finally
    fLock.Leave;
  end;
end;

function TUiEventQueue.TryDequeue(out aEvent: TUiEvent): Boolean;
var
  lIndex: Integer;
  lPendingIndex: Integer;
begin
  Result := False;
  fLock.Enter;
  try
    while fHead < fQueue.Count do
    begin
      lIndex := fHead;
      Inc(fHead);
      if fSuperseded.ContainsKey(lIndex) then
      begin
        fSuperseded.Remove(lIndex);
        Continue;
      end;

      aEvent := fQueue[lIndex];
      if (aEvent.Kind = TUiEventKind.uekProgressUpdate) and
        fPendingProgressIndex.TryGetValue(aEvent.Generation, lPendingIndex) and
        (lPendingIndex = lIndex) then
        fPendingProgressIndex.Remove(aEvent.Generation);
      Dec(fLogicalCount);
      Result := True;
      Break;
    end;
    if fHead = fQueue.Count then
    begin
      fQueue.Clear;
      fPendingProgressIndex.Clear;
      fSuperseded.Clear;
      fHead := 0;
    end else if (fHead > 1024) and (fHead > (fQueue.Count div 2)) then
      Compact;
  finally
    fLock.Leave;
  end;
end;

function TUiEventQueue.Count: Integer;
begin
  fLock.Enter;
  try
    Result := fLogicalCount;
  finally
    fLock.Leave;
  end;
end;

function TUiEventQueue.PeakCount: Integer;
begin
  fLock.Enter;
  try
    Result := fPeakCount;
  finally
    fLock.Leave;
  end;
end;

procedure TUiEventQueue.ResetPeakCount;
begin
  fLock.Enter;
  try
    fPeakCount := fLogicalCount;
  finally
    fLock.Leave;
  end;
end;

procedure TUiEventQueue.Compact;
var
  lCompacted: TList<TUiEvent>;
  lEvent: TUiEvent;
  i: Integer;
  lNewIndex: Integer;
begin
  lCompacted := TList<TUiEvent>.Create;
  try
    fPendingProgressIndex.Clear;
    for i := fHead to fQueue.Count - 1 do
    begin
      if fSuperseded.ContainsKey(i) then
        Continue;
      lEvent := fQueue[i];
      lNewIndex := lCompacted.Add(lEvent);
      if lEvent.Kind = TUiEventKind.uekProgressUpdate then
        fPendingProgressIndex.AddOrSetValue(lEvent.Generation, lNewIndex);
    end;
    fQueue.Free;
    fQueue := lCompacted;
    lCompacted := nil;
    fSuperseded.Clear;
    fHead := 0;
  finally
    lCompacted.Free;
  end;
end;

class function TUiEventPump.Process(const aQueue: TUiEventQueue;
  const aActiveGeneration: Int64; const aMaxEvents: Integer;
  const aMaxMilliseconds: Int64; const aHandler: TUiEventHandler;
  const aClock: TUiClock): TUiEventPumpResult;
var
  lEvent: TUiEvent;
  lStopwatch: TStopwatch;
  lStartMilliseconds: Int64;

  function ElapsedMilliseconds: Int64;
  begin
    if Assigned(aClock) then
      Result := aClock() - lStartMilliseconds
    else
      Result := lStopwatch.ElapsedMilliseconds;
  end;
begin
  Result := Default(TUiEventPumpResult);
  if Assigned(aClock) then
    lStartMilliseconds := aClock()
  else
    lStopwatch := TStopwatch.StartNew;

  while (Result.DequeuedCount < aMaxEvents) and (aMaxEvents > 0) and
    (aMaxMilliseconds > 0) do
  begin
    if (Result.DequeuedCount > 0) and (ElapsedMilliseconds >= aMaxMilliseconds) then
      Break;
    if not aQueue.TryDequeue(lEvent) then
      Break;
    Inc(Result.DequeuedCount);
    if ((lEvent.Generation = 0) or (lEvent.Generation = aActiveGeneration)) and
      Assigned(aHandler) then
    begin
      aHandler(lEvent);
      Inc(Result.DeliveredCount);
    end;
  end;
  Result.ElapsedMilliseconds := ElapsedMilliseconds;
  Result.HasMore := aQueue.Count > 0;
end;

end.
