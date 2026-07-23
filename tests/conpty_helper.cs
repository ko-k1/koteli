// Minimal zero-package ConPTY driver used by tests/test_installers.py.
// Compile with the inbox .NET Framework C# compiler:
//   csc.exe /nologo /out:conpty_helper.exe conpty_helper.cs

using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class ConPtyHelper
{
    private const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
    private const uint PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016;
    private const uint HANDLE_FLAG_INHERIT = 0x00000001;
    private const uint WAIT_OBJECT_0 = 0x00000000;

    [StructLayout(LayoutKind.Sequential)]
    private struct COORD
    {
        internal short X;
        internal short Y;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct STARTUPINFO
    {
        internal int cb;
        internal string lpReserved;
        internal string lpDesktop;
        internal string lpTitle;
        internal int dwX;
        internal int dwY;
        internal int dwXSize;
        internal int dwYSize;
        internal int dwXCountChars;
        internal int dwYCountChars;
        internal int dwFillAttribute;
        internal int dwFlags;
        internal short wShowWindow;
        internal short cbReserved2;
        internal IntPtr lpReserved2;
        internal IntPtr hStdInput;
        internal IntPtr hStdOutput;
        internal IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct STARTUPINFOEX
    {
        internal STARTUPINFO StartupInfo;
        internal IntPtr lpAttributeList;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_INFORMATION
    {
        internal IntPtr hProcess;
        internal IntPtr hThread;
        internal int dwProcessId;
        internal int dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CreatePipe(
        out IntPtr hReadPipe,
        out IntPtr hWritePipe,
        IntPtr lpPipeAttributes,
        int nSize
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetHandleInformation(
        IntPtr hObject,
        uint dwMask,
        uint dwFlags
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern int CreatePseudoConsole(
        COORD size,
        IntPtr hInput,
        IntPtr hOutput,
        uint dwFlags,
        out IntPtr phPC
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern void ClosePseudoConsole(IntPtr hPC);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool InitializeProcThreadAttributeList(
        IntPtr lpAttributeList,
        int dwAttributeCount,
        int dwFlags,
        ref IntPtr lpSize
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool UpdateProcThreadAttribute(
        IntPtr lpAttributeList,
        uint dwFlags,
        IntPtr attribute,
        IntPtr lpValue,
        IntPtr cbSize,
        IntPtr lpPreviousValue,
        IntPtr lpReturnSize
    );

    [DllImport("kernel32.dll")]
    private static extern void DeleteProcThreadAttributeList(IntPtr lpAttributeList);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcessW(
        string lpApplicationName,
        StringBuilder lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFOEX lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadFile(
        IntPtr hFile,
        byte[] lpBuffer,
        int nNumberOfBytesToRead,
        out int lpNumberOfBytesRead,
        IntPtr lpOverlapped
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteFile(
        IntPtr hFile,
        byte[] lpBuffer,
        int nNumberOfBytesToWrite,
        out int lpNumberOfBytesWritten,
        IntPtr lpOverlapped
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    private static void Check(bool success, string operation)
    {
        if (!success)
        {
            throw new InvalidOperationException(
                operation + " failed with Win32 error " + Marshal.GetLastWin32Error()
            );
        }
    }

    private static string Quote(string argument)
    {
        if (argument.Length > 0 && argument.IndexOfAny(new[] { ' ', '\t', '"' }) < 0)
        {
            return argument;
        }
        return "\"" + argument.Replace("\"", "\\\"") + "\"";
    }

    private static string BuildCommandLine(string[] args, int firstCommandArgument)
    {
        var parts = new List<string>();
        for (int index = firstCommandArgument; index < args.Length; index++)
        {
            parts.Add(Quote(args[index]));
        }
        return string.Join(" ", parts.ToArray());
    }

    private static int Run(string[] args)
    {
        if (args.Length < 3)
        {
            Console.Error.WriteLine(
                "usage: conpty_helper <base64-input> <executable> [arguments...]"
            );
            return 125;
        }

        byte[] input = Convert.FromBase64String(args[0]);
        IntPtr pseudoInputRead = IntPtr.Zero;
        IntPtr hostInputWrite = IntPtr.Zero;
        IntPtr hostOutputRead = IntPtr.Zero;
        IntPtr pseudoOutputWrite = IntPtr.Zero;
        IntPtr pseudoConsole = IntPtr.Zero;
        IntPtr attributeList = IntPtr.Zero;
        PROCESS_INFORMATION process = new PROCESS_INFORMATION();
        bool processCreated = false;
        var captured = new MemoryStream();
        Thread reader = null;

        try
        {
            Check(
                CreatePipe(out pseudoInputRead, out hostInputWrite, IntPtr.Zero, 0),
                "CreatePipe(input)"
            );
            Check(
                SetHandleInformation(hostInputWrite, HANDLE_FLAG_INHERIT, 0),
                "SetHandleInformation(input)"
            );
            Check(
                CreatePipe(out hostOutputRead, out pseudoOutputWrite, IntPtr.Zero, 0),
                "CreatePipe(output)"
            );
            Check(
                SetHandleInformation(hostOutputRead, HANDLE_FLAG_INHERIT, 0),
                "SetHandleInformation(output)"
            );

            var size = new COORD { X = 100, Y = 40 };
            int createResult = CreatePseudoConsole(
                size,
                pseudoInputRead,
                pseudoOutputWrite,
                0,
                out pseudoConsole
            );
            if (createResult != 0)
            {
                throw new InvalidOperationException(
                    "CreatePseudoConsole failed with HRESULT 0x" +
                    createResult.ToString("X8")
                );
            }
            CloseHandle(pseudoInputRead);
            pseudoInputRead = IntPtr.Zero;
            CloseHandle(pseudoOutputWrite);
            pseudoOutputWrite = IntPtr.Zero;

            IntPtr attributeSize = IntPtr.Zero;
            InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref attributeSize);
            attributeList = Marshal.AllocHGlobal(attributeSize);
            Check(
                InitializeProcThreadAttributeList(attributeList, 1, 0, ref attributeSize),
                "InitializeProcThreadAttributeList"
            );
            Check(
                UpdateProcThreadAttribute(
                    attributeList,
                    0,
                    (IntPtr)PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                    pseudoConsole,
                    (IntPtr)IntPtr.Size,
                    IntPtr.Zero,
                    IntPtr.Zero
                ),
                "UpdateProcThreadAttribute"
            );

            var startup = new STARTUPINFOEX();
            startup.StartupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFOEX));
            startup.lpAttributeList = attributeList;
            var commandLine = new StringBuilder(BuildCommandLine(args, 1));
            Check(
                CreateProcessW(
                    null,
                    commandLine,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    false,
                    EXTENDED_STARTUPINFO_PRESENT,
                    IntPtr.Zero,
                    null,
                    ref startup,
                    out process
                ),
                "CreateProcessW"
            );
            processCreated = true;

            reader = new Thread(
                delegate()
                {
                    var buffer = new byte[4096];
                    int bytesRead;
                    while (ReadFile(
                        hostOutputRead,
                        buffer,
                        buffer.Length,
                        out bytesRead,
                        IntPtr.Zero
                    ))
                    {
                        if (bytesRead == 0)
                        {
                            break;
                        }
                        captured.Write(buffer, 0, bytesRead);
                    }
                }
            );
            reader.IsBackground = true;
            reader.Start();

            Thread.Sleep(750);
            int bytesWritten;
            Check(
                WriteFile(
                    hostInputWrite,
                    input,
                    input.Length,
                    out bytesWritten,
                    IntPtr.Zero
                ),
                "WriteFile(input)"
            );
            CloseHandle(hostInputWrite);
            hostInputWrite = IntPtr.Zero;

            if (WaitForSingleObject(process.hProcess, 45000) != WAIT_OBJECT_0)
            {
                throw new TimeoutException("ConPTY child did not exit within 45 seconds.");
            }
            uint exitCode;
            Check(GetExitCodeProcess(process.hProcess, out exitCode), "GetExitCodeProcess");

            ClosePseudoConsole(pseudoConsole);
            pseudoConsole = IntPtr.Zero;
            if (reader != null)
            {
                reader.Join(5000);
            }
            byte[] output = captured.ToArray();
            Stream stdout = Console.OpenStandardOutput();
            stdout.Write(output, 0, output.Length);
            stdout.Flush();
            return unchecked((int)exitCode);
        }
        finally
        {
            if (reader != null && reader.IsAlive)
            {
                reader.Join(250);
            }
            if (processCreated)
            {
                CloseHandle(process.hThread);
                CloseHandle(process.hProcess);
            }
            if (attributeList != IntPtr.Zero)
            {
                DeleteProcThreadAttributeList(attributeList);
                Marshal.FreeHGlobal(attributeList);
            }
            if (pseudoConsole != IntPtr.Zero)
            {
                ClosePseudoConsole(pseudoConsole);
            }
            if (pseudoInputRead != IntPtr.Zero)
            {
                CloseHandle(pseudoInputRead);
            }
            if (pseudoOutputWrite != IntPtr.Zero)
            {
                CloseHandle(pseudoOutputWrite);
            }
            if (hostInputWrite != IntPtr.Zero)
            {
                CloseHandle(hostInputWrite);
            }
            if (hostOutputRead != IntPtr.Zero)
            {
                CloseHandle(hostOutputRead);
            }
            captured.Dispose();
        }
    }

    private static int Main(string[] args)
    {
        try
        {
            return Run(args);
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception.ToString());
            return 125;
        }
    }
}
