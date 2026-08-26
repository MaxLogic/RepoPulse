unit TestUiEventQueue;

interface

uses
  System.Generics.Collections, System.SysUtils,
  DUnitX.TestFramework,
  UUiEventQueue;

type
  [TestFixture]
  TUiEventQueueTests = class
  private
    function MakeEvent(const aKind: TUiEventKind; const aGeneration: Int64;
      const aValue: Integer = 0): TUiEvent;
  public
    [Test]
    procedure Queue_CoalescesPendingProgressAtLatestPosition;
    [Test]
    procedure Queue_CompactsWithoutChangingLogicalOrder;
    [Test]
    procedure Queue_PeakCountTracksAndResetsLogicalDepth;
    [Test]
    procedure Pump_StopsAtEventLimitAndPreservesOrder;
    [Test]
    procedure Pump_StopsAtElapsedTimeLimit;
    [Test]
    procedure Pump_DiscardsStaleScanEventsButKeepsUnscopedEvents;
  end;

implementation

procedure TUiEventQueueTests.Queue_PeakCountTracksAndResetsLogicalDepth;
var
  lEvent: TUiEvent;
  lQueue: TUiEventQueue;
begin
  lQueue := TUiEventQueue.Create;
  try
    lQueue.Enqueue(MakeEvent(TUiEventKind.uekLog, 1, 1));
    lQueue.Enqueue(MakeEvent(TUiEventKind.uekLog, 1, 2));
    lQueue.Enqueue(MakeEvent(TUiEventKind.uekProgressUpdate, 1, 3));
    lQueue.Enqueue(MakeEvent(TUiEventKind.uekProgressUpdate, 1, 4));
    Assert.AreEqual(3, lQueue.PeakCount);
    Assert.IsTrue(lQueue.TryDequeue(lEvent));
    Assert.IsTrue(lQueue.TryDequeue(lEvent));
    lQueue.Enqueue(MakeEvent(TUiEventKind.uekLog, 1, 5));
    Assert.AreEqual(3, lQueue.PeakCount);
    lQueue.ResetPeakCount;
    Assert.AreEqual(lQueue.Count, lQueue.PeakCount);
  finally
    lQueue.Free;
  end;
end;

function TUiEventQueueTests.MakeEvent(const aKind: TUiEventKind;
  const aGeneration: Int64; const aValue: Integer): TUiEvent;
begin
  Result := Default(TUiEvent);
  Result.Kind := aKind;
  Result.Generation := aGeneration;
  Result.ProgressValue := aValue;
  Result.Text := IntToStr(aValue);
end;

procedure TUiEventQueueTests.Queue_CoalescesPendingProgressAtLatestPosition;
var
  lQueue: TUiEventQueue;
  lEvent: TUiEvent;
begin
  lQueue := TUiEventQueue.Create;
  try
    lQueue.Enqueue(MakeEvent(TUiEventKind.uekProgressUpdate, 7, 1));
    lQueue.Enqueue(MakeEvent(TUiEventKind.uekLog, 7, 10));
    lQueue.Enqueue(MakeEvent(TUiEventKind.uekProgressUpdate, 7, 2));
    lQueue.Enqueue(MakeEvent(TUiEventKind.uekProgressUpdate, 7, 3));

    Assert.AreEqual(2, lQueue.Count);
    Assert.IsTrue(lQueue.TryDequeue(lEvent));
    Assert.AreEqual(TUiEventKind.uekLog, lEvent.Kind);
    Assert.IsTrue(lQueue.TryDequeue(lEvent));
    Assert.AreEqual(TUiEventKind.uekProgressUpdate, lEvent.Kind);
    Assert.AreEqual(3, lEvent.ProgressValue);
  finally
    lQueue.Free;
  end;
end;

procedure TUiEventQueueTests.Queue_CompactsWithoutChangingLogicalOrder;
var
  lQueue: TUiEventQueue;
  lEvent: TUiEvent;
  i: Integer;
begin
  lQueue := TUiEventQueue.Create;
  try
    for i := 1 to 2500 do
      lQueue.Enqueue(MakeEvent(TUiEventKind.uekLog, 3, i));
    for i := 1 to 1500 do
    begin
      Assert.IsTrue(lQueue.TryDequeue(lEvent));
      Assert.AreEqual(i, lEvent.ProgressValue);
    end;
    Assert.AreEqual(1000, lQueue.Count);
    for i := 1501 to 2500 do
    begin
      Assert.IsTrue(lQueue.TryDequeue(lEvent));
      Assert.AreEqual(i, lEvent.ProgressValue);
    end;
    Assert.AreEqual(0, lQueue.Count);
  finally
    lQueue.Free;
  end;
end;

procedure TUiEventQueueTests.Pump_StopsAtEventLimitAndPreservesOrder;
var
  lQueue: TUiEventQueue;
  lValues: TList<Integer>;
  lResult: TUiEventPumpResult;
  i: Integer;
begin
  lQueue := TUiEventQueue.Create;
  lValues := TList<Integer>.Create;
  try
    for i := 1 to 10 do
      lQueue.Enqueue(MakeEvent(TUiEventKind.uekLog, 4, i));

    lResult := TUiEventPump.Process(lQueue, 4, 3, 1000,
      procedure(const aEvent: TUiEvent)
      begin
        lValues.Add(aEvent.ProgressValue);
      end);

    Assert.AreEqual(3, lResult.DequeuedCount);
    Assert.AreEqual(3, lResult.DeliveredCount);
    Assert.IsTrue(lResult.HasMore);
    Assert.AreEqual(7, lQueue.Count);
    Assert.AreEqual(1, lValues[0]);
    Assert.AreEqual(2, lValues[1]);
    Assert.AreEqual(3, lValues[2]);
  finally
    lValues.Free;
    lQueue.Free;
  end;
end;

procedure TUiEventQueueTests.Pump_StopsAtElapsedTimeLimit;
var
  lQueue: TUiEventQueue;
  lNow: Int64;
  lResult: TUiEventPumpResult;
  i: Integer;
begin
  lQueue := TUiEventQueue.Create;
  try
    for i := 1 to 10 do
      lQueue.Enqueue(MakeEvent(TUiEventKind.uekLog, 9, i));
    lNow := 0;

    // A deterministic clock avoids wall-clock jitter in this boundary test.
    lResult := TUiEventPump.Process(lQueue, 9, 10, 10,
      procedure(const aEvent: TUiEvent)
      begin
        Inc(lNow, 5);
      end,
      function: Int64
      begin
        Result := lNow;
      end);

    Assert.AreEqual(2, lResult.DequeuedCount);
    Assert.AreEqual(2, lResult.DeliveredCount);
    Assert.AreEqual(Int64(10), lResult.ElapsedMilliseconds);
    Assert.IsTrue(lResult.HasMore);
  finally
    lQueue.Free;
  end;
end;

procedure TUiEventQueueTests.Pump_DiscardsStaleScanEventsButKeepsUnscopedEvents;
var
  lQueue: TUiEventQueue;
  lGenerations: TList<Int64>;
  lResult: TUiEventPumpResult;
begin
  lQueue := TUiEventQueue.Create;
  lGenerations := TList<Int64>.Create;
  try
    lQueue.Enqueue(MakeEvent(TUiEventKind.uekRepoResult, 11, 1));
    lQueue.Enqueue(MakeEvent(TUiEventKind.uekActionResult, 0, 2));
    lQueue.Enqueue(MakeEvent(TUiEventKind.uekRepoResult, 12, 3));

    lResult := TUiEventPump.Process(lQueue, 12, 10, 1000,
      procedure(const aEvent: TUiEvent)
      begin
        lGenerations.Add(aEvent.Generation);
      end);

    Assert.AreEqual(3, lResult.DequeuedCount);
    Assert.AreEqual(2, lResult.DeliveredCount);
    Assert.AreEqual(Int64(0), lGenerations[0]);
    Assert.AreEqual(Int64(12), lGenerations[1]);
  finally
    lGenerations.Free;
    lQueue.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUiEventQueueTests);

end.
