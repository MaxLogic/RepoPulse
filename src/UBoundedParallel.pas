unit UBoundedParallel;

interface

uses
  System.SysUtils, System.Threading;

type
  TBoundedParallel = class
  public
    class procedure Run(const aItemCount, aMaxThreads: Integer;
      const aWork: TProc<Integer>); static;
  end;

implementation

class procedure TBoundedParallel.Run(const aItemCount, aMaxThreads: Integer;
  const aWork: TProc<Integer>);
var
  lPool: TThreadPool;
  lThreadCount: Integer;
begin
  if aItemCount <= 0 then
    Exit;
  if aMaxThreads < 1 then
    raise EArgumentOutOfRangeException.Create('Maximum thread count must be at least one.');
  if aMaxThreads < aItemCount then
    lThreadCount := aMaxThreads
  else
    lThreadCount := aItemCount;

  lPool := TThreadPool.Create;
  try
    lPool.UnlimitedWorkerThreadsWhenBlocked := False;
    lPool.SetMaxWorkerThreads(lThreadCount);
    lPool.SetMinWorkerThreads(lThreadCount);
    TParallel.For(0, aItemCount - 1,
      procedure(aIndex: Integer; aLoopState: TParallel.TLoopState)
      begin
        aWork(aIndex);
      end,
      lPool);
  finally
    lPool.Free;
  end;
end;

end.
