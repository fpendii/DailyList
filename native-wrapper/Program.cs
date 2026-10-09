using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Windows.Forms;

namespace DaftarHarian
{
    internal static class Program
    {
        private static readonly KeyValuePair<string, string>[] Resources =
        {
            new KeyValuePair<string, string>("DaftarHarian.Script", "DailyListPopup.ps1"),
            new KeyValuePair<string, string>("DaftarHarian.Icon", @"assets\app-icon.ico"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat1.OpenEyes", @"assets\cat-expressions-1\buka mata.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat1.Angry", @"assets\cat-expressions-1\marah.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat1.Blink", @"assets\cat-expressions-1\merem.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat1.Yawn", @"assets\cat-expressions-1\nguap.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat1.Sleep", @"assets\cat-expressions-1\tidur.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat2.Confused", @"assets\cat-expressions-2\Bingung.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat2.Love", @"assets\cat-expressions-2\Cinta.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat2.Nervous", @"assets\cat-expressions-2\Grogi.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat2.Tired", @"assets\cat-expressions-2\lelah.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat2.Shy", @"assets\cat-expressions-2\Malu.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat2.Panic", @"assets\cat-expressions-2\Panik.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat2.Curious", @"assets\cat-expressions-2\Penasaran.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat2.Sad", @"assets\cat-expressions-2\Sedih.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat2.Happy", @"assets\cat-expressions-2\Senang.png"),
            new KeyValuePair<string, string>("DaftarHarian.Assets.Cat2.Surprised", @"assets\cat-expressions-2\Terkejut.png")
        };

        [STAThread]
        private static void Main()
        {
            try
            {
                string appDirectory = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "DaftarHarian");
                Directory.CreateDirectory(appDirectory);
                ExtractResources(appDirectory);
                Environment.SetEnvironmentVariable("DAFTAR_HARIAN_APP_DIR", appDirectory, EnvironmentVariableTarget.Process);
                RunScriptInStaRunspace();
            }
            catch (Exception error)
            {
                MessageBox.Show(
                    "Daftar Harian tidak dapat dijalankan.\n\n" + error.Message,
                    "Daftar Harian",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }

        private static void RunScriptInStaRunspace()
        {
            InitialSessionState sessionState = InitialSessionState.CreateDefault();
            using (Runspace runspace = RunspaceFactory.CreateRunspace(sessionState))
            {
                // WPF requires the PowerShell runspace itself to be STA. ReuseThread keeps
                // the window on this same application process for the whole UI lifetime.
                runspace.ApartmentState = System.Threading.ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.ReuseThread;
                runspace.Open();

                using (PowerShell engine = PowerShell.Create())
                {
                    engine.Runspace = runspace;
                    engine.AddScript(ReadTextResource("DaftarHarian.Script"));
                    engine.Invoke();

                    if (engine.Streams.Error.Count > 0)
                    {
                        throw new InvalidOperationException(engine.Streams.Error[0].ToString());
                    }
                }
            }
        }

        private static string ReadTextResource(string resourceName)
        {
            using (Stream source = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName))
            {
                if (source == null)
                {
                    throw new InvalidOperationException("Skrip aplikasi tidak ditemukan.");
                }
                using (StreamReader reader = new StreamReader(source))
                {
                    return reader.ReadToEnd();
                }
            }
        }

        private static void ExtractResources(string appDirectory)
        {
            Assembly assembly = Assembly.GetExecutingAssembly();
            foreach (KeyValuePair<string, string> resource in Resources)
            {
                string destination = Path.Combine(appDirectory, resource.Value);
                string directory = Path.GetDirectoryName(destination);
                if (!Directory.Exists(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                using (Stream source = assembly.GetManifestResourceStream(resource.Key))
                {
                    if (source == null)
                    {
                        throw new InvalidOperationException("Berkas aplikasi tidak ditemukan: " + resource.Key);
                    }
                    using (FileStream target = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.Read))
                    {
                        source.CopyTo(target);
                    }
                }
            }
        }
    }
}
