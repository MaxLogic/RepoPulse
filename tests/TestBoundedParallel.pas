unit TestBoundedParallel;

interface

uses
  System.Classes, System.SyncObjs, System.SysUtils,

  DUnitX.TestFramework,
  UBoundedParallel;

type
  [TestFixture]
  TBoundedParallelTests = class
  public
    [Test]
    procedure Run_NeverExceedsConfiguredConcurrency;
  end;

implementation

procedure TBoundedParallelTests.Run_NeverExceedsConfiguredConcurrency;
var
  lActive: Integer;
  lMaxActive: Integer;
  lRelease: TEvent;
  lRunner: TThread;
  lRunnerError: string;
  lThreeStarted: TEvent;
  lTooManyStarted: TEvent;
begin
  lActive := 0;
  lMaxActive := 0;
  lRunnerError := '';
  lRelease := TEvent.Create(nil, True, False, '');
  lThreeStarted := TEvent.Create(nil, True, False, '');
  lTooManyStarted := TEvent.Create(nil, True, False, '');
  lRunner := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        TBoundedParallel.Run(8, 3,
          procedure(aIndex: Integer)
          var
            lCurrent: Integer;
            lObserved: Integer;
          begin
            if aIndex < 0 then
              Exit;
            lCurrent := TInterlocked.Increment(lActive);
            repeat
              lObserved := lMaxActive;
              if lCurrent <= lObserved then
                Break;
            until TInterlocked.CompareExchange(lMaxActive, lCurrent, lObserved) = lObserved;
            if lCurrent >= 3 then
              lThreeStarted.SetEvent;
            if lCurrent > 3 then
              lTooManyStarted.SetEvent;
            lRelease.WaitFor(5000);
            TInterlocked.Decrement(lActive);
          end);
      except
        on E: Exception do
          lRunnerError := E.ClassName + ': ' + E.Message;
      end;
    end);
  lRunner.FreeOnTerminate := False;
  try
    lRunner.Start;
    Assert.AreEqual(TWaitResult.wrSignaled, lThreeStarted.WaitFor(5000));
    Assert.AreEqual(TWaitResult.wrTimeout, lTooManyStarted.WaitFor(250));
    lRelease.SetEvent;
    lRunner.WaitFor;
    Assert.AreEqual('', lRunnerError);
    Assert.IsTrue(lMaxActive <= 3, Format('Observed %d concurrent workers.', [lMaxActive]));
  finally
    lRelease.SetEvent;
    lRunner.WaitFor;
    lRunner.Free;
    lTooManyStarted.Free;
    lThreeStarted.Free;
    lRelease.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBoundedParallelTests);

end.
