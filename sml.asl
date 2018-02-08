state("gambatte") {}
state("gambatte_qt") {}

startup
{
    vars.bossDefeated = 0;
    vars.stopwatch = new Stopwatch();

    vars.timer_OnStart = (EventHandler)((s, e) =>
    {
        vars.splits = vars.GetSplitList();
    });
    timer.OnStart += vars.timer_OnStart;

    vars.FindOffsets = (Action<Process>)((proc) => 
    {
        if (vars.ptrOffset == IntPtr.Zero)
        {
            print("[Autosplitter] Scanning memory");
            var target = new SigScanTarget(0, "05 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ?? ?? ?? ?? ?? ?? ?? ?? F8 00 00 00");

            var ptrOffset = IntPtr.Zero;
            foreach (var page in proc.MemoryPages())
            {
                var scanner = new SignatureScanner(proc, page.BaseAddress, (int)page.RegionSize);

                if ((ptrOffset = scanner.Scan(target)) != IntPtr.Zero)
                    break;
            }

            vars.ptrOffset = ptrOffset;
            vars.hramOffset = vars.ptrOffset + 0x1E0;
            vars.wramPtr = new MemoryWatcher<int>(vars.ptrOffset - 0x20);
        }

        if (vars.ptrOffset != IntPtr.Zero)
        {
            vars.wramPtr.Update(proc);
            vars.wramOffset = (IntPtr)vars.wramPtr.Current;
        }

        if (vars.wramOffset != IntPtr.Zero && vars.hramOffset != IntPtr.Zero)
        {
            print("[Autosplitter] VRAM: " + vars.ptrOffset.ToString("X8"));
            print("[Autosplitter] WRAM: " + vars.wramOffset.ToString("X8"));
            print("[Autosplitter] HRAM: " + vars.hramOffset.ToString("X8"));
        }
    });

    vars.GetWatcherList = (Func<IntPtr, IntPtr, MemoryWatcherList>)((wramOffset, hramOffset) =>
    {   
        return new MemoryWatcherList
        {	
			new MemoryWatcher<byte>(wramOffset - 0x27E0) { Name = "scoreHundredThousand" },
			new MemoryWatcher<byte>(wramOffset - 0x27DF) { Name = "scoreTenThousand" },
			new MemoryWatcher<byte>(wramOffset - 0x27DE) { Name = "scoreThousand" },
			new MemoryWatcher<byte>(wramOffset - 0x27D2) { Name = "stage" },
			new MemoryWatcher<byte>(wramOffset - 0x27D4) { Name = "world" },   
			new MemoryWatcher<byte>(wramOffset - 0x27F9) { Name = "lives" },		
			new MemoryWatcher<byte>(wramOffset - 0x2693) { Name = "reset" },
			new MemoryWatcher<byte>(wramOffset + 0x1F01) { Name = "DemoCheck" }, 
			new MemoryWatcher<byte>(wramOffset - 0x27CF) { Name = "timeHundred" },
			new MemoryWatcher<byte>(wramOffset - 0x27CE) { Name = "timeTen" },
			new MemoryWatcher<byte>(wramOffset - 0x27CD) { Name = "time" },
			new MemoryWatcher<Int16>(wramOffset - 0x27FA) { Name = "livesTen" },
			new MemoryWatcher<Int16>(wramOffset - 0x27F9) { Name = "lives" },			
        };
    });
	
	
}

init
{
    vars.ptrOffset = IntPtr.Zero;
    vars.wramOffset = IntPtr.Zero;
    vars.hramOffset = IntPtr.Zero;
    
    vars.wramPtr = new MemoryWatcher<byte>(IntPtr.Zero);

    vars.watchers = new MemoryWatcherList();
    vars.splits = new List<Tuple<string, List<Tuple<string, uint>>>>();

    vars.stopwatch.Restart();
}

update
{
    if (vars.stopwatch.ElapsedMilliseconds > 1500)
    {
        vars.FindOffsets(game);

        if (vars.wramOffset != IntPtr.Zero && vars.hramOffset != IntPtr.Zero)
        {
            vars.watchers = vars.GetWatcherList(vars.wramOffset, vars.hramOffset);
            vars.stopwatch.Reset();
        }
        else
        {
            vars.stopwatch.Restart();
            return false;
        }
    }
    else if (vars.watchers.Count == 0)
        return false;

    vars.wramPtr.Update(game);

    if (vars.wramPtr.Changed)
    {
        vars.FindOffsets(game);
        vars.watchers = vars.GetWatcherList(vars.wramOffset, vars.hramOffset);
    }

    vars.watchers.UpdateAll(game);
}

start
{
	
	print("[Autosplitter] (DemoCheck): " + vars.watchers["DemoCheck"].Current + "-" + vars.watchers["DemoCheck"].Old);
	

    return ((vars.watchers["world"].Current == 1) && (vars.watchers["stage"].Current == 1) && (vars.watchers["DemoCheck"].Current != vars.watchers["DemoCheck"].Old) );
}

reset
{
    return (vars.watchers["world"].Current) == 0x2C && vars.watchers["stage"].Current == 0x2C && vars.watchers["lives"].Current == 0x3C;
}

split
{
	int current_score = (vars.watchers["scoreHundredThousand"].Current * 100) +  (vars.watchers["scoreTenThousand"].Current * 10) + vars.watchers["scoreThousand"].Current;
	int old_score = (vars.watchers["scoreHundredThousand"].Old * 100) + (vars.watchers["scoreTenThousand"].Old * 10) + vars.watchers["scoreThousand"].Old;
	int currentTime = (vars.watchers["timeHundred"].Current * 100) +  (vars.watchers["timeTen"].Current * 10) + vars.watchers["time"].Current;
	int lives = Convert.ToInt32(vars.watchers["livesTen"].Current.ToString("X4").Substring(0, 2), 16);
	lives +=  Convert.ToInt32(vars.watchers["livesTen"].Current.ToString("X4").Substring(2, 2), 16) * 10;
	
	int oldLives = Convert.ToInt32(vars.watchers["livesTen"].Old.ToString("X4").Substring(0, 2), 16);
	lives +=  Convert.ToInt32(vars.watchers["livesTen"].Old.ToString("X4").Substring(2, 2), 16) * 10;
	
	if(vars.watchers["world"].Current == 4 && vars.watchers["stage"].Current == 3)
	{

		if(currentTime < 380)
		{
			if((oldLives - lives) == 1)
			{
				vars.bossDefeated  = 0;
			}
			
			if(current_score - old_score == 5)
			{
				print("[Autosplitter] (DemoCheck): " + current_score + "-" + old_score);
				vars.bossDefeated++;
			}
			
			if(vars.bossDefeated == 2)
			{
				return true;
			}
		}
	}
	if(vars.watchers["stage"].Old == 0x2C && vars.watchers["stage"].Current == 1)
	{
		return true;
	}
	else
	{
		return vars.watchers["stage"].Current != vars.watchers["stage"].Old && vars.watchers["stage"].Current != 0x2C && vars.watchers["stage"].Old != 0x2C && vars.watchers["stage"].Current != 0x00 && vars.watchers["stage"].Old != 0x00;
	}
}

shutdown
{
    timer.OnStart -= vars.timer_OnStart;
}