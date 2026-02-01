defmodule BaptismBackend.Certificate do
  @moduledoc """
  Module for generating baptism certificates.
  """

  alias BaptismBackend.S3Storage
  alias BaptismBackend.Struct.Profile

  require Logger

  @work_dir "/tmp/python-script"
  @template_path Path.join(@work_dir, "template.pptx")

  @doc """
  Generates a baptism certificate for the given profile data.
  """

  def generate_certificate(%Profile{} = profile, config) do
    with :ok <- ensure_directory(),
         :ok <- maybe_fetch_template(),
         :ok <- fetch_headshot(profile.id),
         :ok <- python_generate_pptx(profile, config),
         :ok <- generate_pptx_preview(profile.id),
         :ok <- upload_pptx(profile.id),
         :ok <- upload_pptx_preview(profile.id) do
      cleanup_files(profile.id)
      Logger.info("Successfully generated certificate for profile #{profile.id}")
      :ok
    else
      error ->
        Logger.error("Failed to generate certificate for profile #{profile.id}: #{inspect(error)}")
        cleanup_files(profile.id)
        error
    end
  end

  defp maybe_fetch_template do
    S3Storage.download_template(@template_path)
  end

  defp ensure_directory do
    Logger.info("Ensuring working directory #{@work_dir} exists")
    with :ok <- File.mkdir_p(@work_dir),
         :ok <- copy_python_script() do
      :ok
    end
  end

  defp copy_python_script do
    Logger.info("Copying python script to #{@work_dir}")

    # In production (Docker), python folder is at /app/python
    # In dev, it's relative to priv_dir
    source = if File.exists?("/app/python/script.py") do
      "/app/python/script.py"
    else
      Path.join(:code.priv_dir(:baptism_backend), "../python/script.py")
    end

    dest = Path.join(@work_dir, "script.py")

    # Always copy to ensure we have the latest version
    case File.cp(source, dest) do
      :ok -> :ok
      {:error, reason} -> {:error, {:copy_script_failed, reason}}
    end
  end

  defp fetch_headshot(id) do
    Logger.info("Fetching headshot for profile #{id}")
    local_path = Path.join(@work_dir, "headshot_#{id}.jpg")
    S3Storage.download_headshot(id, local_path)
  end

  defp upload_pptx(id) do
    Logger.info("Uploading PPTX for profile #{id}")
    local_path = Path.join(@work_dir, "output_#{id}.pptx")
    S3Storage.upload_file("certificates/#{id}.pptx", local_path)
  end

  defp upload_pptx_preview(id) do
    Logger.info("Uploading PDF preview for profile #{id}")
    local_path = Path.join(@work_dir, "output_#{id}.pdf")
    S3Storage.upload_pdf_preview("certificate_previews/#{id}.pdf", local_path)
  end

  defp cleanup_files(id) do
    File.rm(Path.join(@work_dir, "headshot_#{id}.jpg"))
    File.rm(Path.join(@work_dir, "output_#{id}.pptx"))
    File.rm(Path.join(@work_dir, "output_#{id}.pdf"))
  end

  defp generate_pptx_preview(id) do
    output_path = Path.join(@work_dir, "output_#{id}.pptx")
    Logger.info("Generating PDF preview for #{id}")
    case System.cmd("soffice", ["--headless", "--convert-to", "pdf", output_path], cd: @work_dir) do
      {_output, 0} -> :ok
      {error, _code} -> {:error, {:soffice_failed, error}}
    end
  end

  defp python_generate_pptx(profile, config) do
    Logger.info("Generating PPTX for profile #{profile.id}")
    input = build_pptx_input(profile, config)
    script_path = Path.join(@work_dir, "script.py")
    input_file = Path.join(@work_dir, "input_#{profile.id}.txt")

    # Write input to file
    case File.write(input_file, input) do
      :ok ->
        Logger.info("Running python script for profile #{profile.id}")
        result = System.cmd("python3", [script_path, input_file],
          cd: @work_dir,
          stderr_to_stdout: true
        )
        Logger.info("Python script output for profile #{profile.id}: #{elem(result, 0)}")

        # Clean up input file
        File.rm(input_file)

        case result do
          {_output, 0} -> :ok
          {error, _code} -> {:error, {:python_script_failed, error}}
        end

      {:error, reason} ->
        {:error, {:write_input_failed, reason}}
    end
  end

  defp build_pptx_input(profile, config) do
    headshot_config = Map.get(config, "headshot", "left=5 top=1 w=3")
    name_config = Map.get(config, "name", "left=1 top=1 w=6 h=1.5 fontsz=18")
    birthday_config = Map.get(config, "birthday", "left=1 top=2.5 w=6 h=1.5 fontsz=18 font=\"Times New Roman\"")
    bap_day_config = Map.get(config, "baptism_day", "left=1 top=4 w=6 h=1.5 fontsz=18 font=\"Times New Roman\"")
    bap_month_config = Map.get(config, "baptism_month", "left=2 top=4 w=6 h=1.5 fontsz=18 font=\"Times New Roman\"")
    bap_year_config = Map.get(config, "baptism_year", "left=3 top=4 w=6 h=1.5 fontsz=18 font=\"Times New Roman\"")
    sign_date_config = Map.get(config, "sign_date", "left=1 top=5.5 w=6 h=1.5 fontsz=18 font=\"Times New Roman\"")

    """
    template.pptx output_#{profile.id}.pptx
    img headshot_#{profile.id}.jpg
    #{headshot_config}
    txt #{profile.name_pinyin} #{profile.name_cn}
    #{name_config} align=left
    txt #{format_date(profile.birthday)}
    #{birthday_config} align=left
    txt #{format_day(profile.baptism_date)}
    #{bap_day_config} align=left
    txt #{format_month(profile.baptism_date)}
    #{bap_month_config} align=left
    txt #{format_year(profile.baptism_date)}
    #{bap_year_config} align=left
    txt #{format_date(Date.utc_today())}
    #{sign_date_config} align=left
    """
  end

  defp format_day(nil), do: ""
  defp format_day(%Date{} = date), do: Calendar.strftime(date, "%d")

  defp format_month(nil), do: ""
  defp format_month(%Date{} = date), do: Calendar.strftime(date, "%B")

  defp format_year(nil), do: ""
  defp format_year(%Date{} = date), do: Calendar.strftime(date, "%Y")

  defp format_date(nil), do: ""
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%B %d, %Y")
end
