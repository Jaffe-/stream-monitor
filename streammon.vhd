library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity stream_monitor is
  generic (
    STREAM_WIDTH : integer
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    -- Register interface
    s_axi_ctrl_status_awaddr  : in  std_logic_vector(4 downto 0);
    s_axi_ctrl_status_awprot  : in  std_logic_vector(2 downto 0);
    s_axi_ctrl_status_awvalid : in  std_logic;
    s_axi_ctrl_status_awready : out std_logic;
    s_axi_ctrl_status_wdata   : in  std_logic_vector(31 downto 0);
    s_axi_ctrl_status_wstrb   : in  std_logic_vector(3 downto 0);
    s_axi_ctrl_status_wvalid  : in  std_logic;
    s_axi_ctrl_status_wready  : out std_logic;
    s_axi_ctrl_status_bresp   : out std_logic_vector(1 downto 0);
    s_axi_ctrl_status_bvalid  : out std_logic;
    s_axi_ctrl_status_bready  : in  std_logic;
    s_axi_ctrl_status_araddr  : in  std_logic_vector(4 downto 0);
    s_axi_ctrl_status_arprot  : in  std_logic_vector(2 downto 0);
    s_axi_ctrl_status_arvalid : in  std_logic;
    s_axi_ctrl_status_arready : out std_logic;
    s_axi_ctrl_status_rdata   : out std_logic_vector(31 downto 0);
    s_axi_ctrl_status_rresp   : out std_logic_vector(1 downto 0);
    s_axi_ctrl_status_rvalid  : out std_logic;
    s_axi_ctrl_status_rready  : in  std_logic;

    in_stream_tvalid : in  std_logic;
    in_stream_tready : out std_logic;
    in_stream_tlast  : in  std_logic;
    in_stream_tdata  : in  std_logic_vector(STREAM_WIDTH-1 downto 0);

    out_stream_tvalid : out std_logic;
    out_stream_tready : in  std_logic;
    out_stream_tlast  : out std_logic;
    out_stream_tdata  : out std_logic_vector(STREAM_WIDTH-1 downto 0)
    );
end stream_monitor;

architecture rtl of stream_monitor is
  type state_t is (STATE_IDLE, STATE_RUNNING);

  signal control_reg       : std_logic_vector(31 downto 0);
  signal total_counter     : integer;
  signal handshake_counter : integer;
  signal notready_counter  : integer;
  signal notvalid_counter  : integer;
  signal state             : state_t;

  signal total_counter_slv     : std_logic_vector(31 downto 0);
  signal handshake_counter_slv : std_logic_vector(31 downto 0);
  signal notready_counter_slv  : std_logic_vector(31 downto 0);
  signal notvalid_counter_slv  : std_logic_vector(31 downto 0);

  signal handshake     : std_logic;
  signal reset_bit     : std_logic;
  signal reset_bit_reg : std_logic;
  signal reset_pulse   : std_logic;
  signal start_bit     : std_logic;
  signal start_bit_reg : std_logic;
  signal start_pulse   : std_logic;
begin
  out_stream_tdata  <= in_stream_tdata;
  out_stream_tvalid <= in_stream_tvalid;
  out_stream_tlast  <= in_stream_tlast;
  in_stream_tready  <= out_stream_tready;

  total_counter_slv     <= std_logic_vector(to_unsigned(total_counter, 32));
  handshake_counter_slv <= std_logic_vector(to_unsigned(handshake_counter, 32));
  notready_counter_slv  <= std_logic_vector(to_unsigned(notready_counter, 32));
  notvalid_counter_slv  <= std_logic_vector(to_unsigned(notvalid_counter, 32));

  i_register_interface : entity work.register_interface
    generic map (
      C_S_AXI_DATA_WIDTH => 32,
      C_S_AXI_ADDR_WIDTH => 5)
    port map (
      control_reg          => control_reg,
      total_counter_in     => total_counter_slv,
      handshake_counter_in => handshake_counter_slv,
      notready_counter_in  => notready_counter_slv,
      notvalid_counter_in  => notvalid_counter_slv,

      s_axi_aclk    => clk,
      s_axi_aresetn => aresetn,
      s_axi_awaddr  => s_axi_ctrl_status_awaddr,
      s_axi_awprot  => s_axi_ctrl_status_awprot,
      s_axi_awvalid => s_axi_ctrl_status_awvalid,
      s_axi_awready => s_axi_ctrl_status_awready,
      s_axi_wdata   => s_axi_ctrl_status_wdata,
      s_axi_wstrb   => s_axi_ctrl_status_wstrb,
      s_axi_wvalid  => s_axi_ctrl_status_wvalid,
      s_axi_wready  => s_axi_ctrl_status_wready,
      s_axi_bresp   => s_axi_ctrl_status_bresp,
      s_axi_bvalid  => s_axi_ctrl_status_bvalid,
      s_axi_bready  => s_axi_ctrl_status_bready,
      s_axi_araddr  => s_axi_ctrl_status_araddr,
      s_axi_arprot  => s_axi_ctrl_status_arprot,
      s_axi_arvalid => s_axi_ctrl_status_arvalid,
      s_axi_arready => s_axi_ctrl_status_arready,
      s_axi_rdata   => s_axi_ctrl_status_rdata,
      s_axi_rresp   => s_axi_ctrl_status_rresp,
      s_axi_rvalid  => s_axi_ctrl_status_rvalid,
      s_axi_rready  => s_axi_ctrl_status_rready);

  handshake <= in_stream_tvalid and out_stream_tready;
  start_bit <= control_reg(0);
  reset_bit <= control_reg(1);

  reset_bit_reg <= reset_bit when rising_edge(clk);
  start_bit_reg <= start_bit when rising_edge(clk);

  reset_pulse <= not reset_bit_reg and reset_bit;
  start_pulse <= not start_bit_reg and start_bit;

  -- Counter
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        state <= STATE_IDLE;
      else
        if (state = STATE_IDLE and (start_pulse = '1' or handshake = '1')) then
          state             <= STATE_RUNNING;
          total_counter     <= 1;
          handshake_counter <= 1;
          notready_counter  <= 0;
          notvalid_counter  <= 0;
        end if;

        if (state = STATE_RUNNING) then
          if (reset_pulse = '1') then
            state <= STATE_IDLE;
          end if;

          total_counter <= total_counter + 1;
          if (handshake = '1') then
            handshake_counter <= handshake_counter + 1;
            if (in_stream_tlast = '1') then
              state <= STATE_IDLE;
            end if;
          elsif (out_stream_tready = '0') then
            notready_counter <= notready_counter + 1;
          elsif (in_stream_tvalid = '0') then
            notvalid_counter <= notvalid_counter + 1;
          end if;
        end if;
      end if;
    end if;
  end process;
end rtl;
