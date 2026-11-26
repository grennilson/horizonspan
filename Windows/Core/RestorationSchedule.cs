using System;
using System.Threading;
using System.Threading.Tasks;

namespace ScreenSpan
{
    public static class RestorationSchedule
    {
        public static async Task Run(bool startup, Func<int, CancellationToken, Task> wait,
            Func<bool> enabled, Func<Task> attempt, Action<Exception> failed, CancellationToken token)
        {
            var delays = startup ? new[] { 650, 1500, 4000, 8000, 15000 } : new[] { 650, 1500, 4000 };
            foreach (int delay in delays)
            {
                try { await wait(delay, token); }
                catch (OperationCanceledException) when (token.IsCancellationRequested) { return; }
                if (token.IsCancellationRequested || !enabled()) return;
                try { await attempt(); }
                catch (OperationCanceledException) when (token.IsCancellationRequested) { return; }
                catch (Exception error) { failed(error); }
            }
        }
    }
}
