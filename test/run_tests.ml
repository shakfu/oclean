let () =
  Harness.run
    [
      Test_util.tests;
      Test_glob.tests;
      Test_preset.tests;
      Test_scan.tests;
      Test_report.tests;
      Test_config.tests;
      Test_delete.tests;
      Test_cli.tests;
      Test_progress.tests;
      Test_main.tests;
    ]
