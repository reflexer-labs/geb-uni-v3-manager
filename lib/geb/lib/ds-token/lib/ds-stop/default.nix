{ solidityPackage, dappsys }: solidityPackage {
  name = "ds-stop";
  deps = with dappsys; [ds-auth ds-note ds-test];
  src = ./src;
}
