using Gurobi,JuMP
using Plots, Random, Printf, XLSX, CSV, DataFrames, Distributions

# SETS

CONVENTIONAL_GENERATORS=["G1","G2","G3","G4","G5","G6","G7","G8","G9","G10","G11","G12"]
G=length(CONVENTIONAL_GENERATORS)

WIND_FARMS=["W1","W2","W3","W4"]
W=length(WIND_FARMS)

DEMANDS=["D1","D2","D3","D4","D5","D6","D7","D8","D9","D10","D11","D12","D13","D14","D15","D16","D17"]
D=length(DEMANDS)

WIND_AND_GENERATOR=["W1","W2","W3","W4","G1","G2","G3","G4","G5","G6","G7","G8","G9","G10","G11","G12"]

TIME_SLOT=["00-01","01-02","02-03","03-04","04-05","05-06","06-07","07-08","08-09","09-10","10-11","11-12","12-13","13-14","14-15","15-16","16-17","17-18","18-19","19-20","20-21","21-22","22-23","23-24"]
T=length(TIME_SLOT)



# DATA

# Conventional generators [length: 12]
Location_G = [1 2 7 13 15 15 16 18 21 22 23 23] # node
Production_cost_G = [13.32 13.32 20.7 20.93 26.11 10.52 10.52 6.02 5.47 7 10.52 10.89] #[$/MW]
Upward_reserve_cost_WG = [0 0 0 0 1.68 1.68 3.30 4.07 1.89 5.48 5.48 4.98 5.53 8.00 3.45 5.11] #[$/MW]
Downward_reserve_cost_WG = [0 0 0 0 2.32 2.32 4.67 3.93 3.11 3.52 3.52 5.02 4.97 6.00 2.52 2.89] #[$/MW]
Capacity_G = [106.4 106.4 245 413.7 42 108.5 108.5 280 280 210 217 245] #MW
Maximum_upward_reserve_provision_capability_G = [0 0 0 0 48 48 84 216 42 36 36 60 60 48 72 48] #MW
Maximum_downward_reserve_provision_capability_G = [0 0 0 0 48 48 84 216 42 36 36 60 60 48 72 48] #MW


# Wind farms [length: 4]
Location_W = [3 5 16 21] #node
Installed_capacity_W= [500 500 300 300] #[MW]
Day_ahead_forecast_W = [120.54 115.52 53.34 38.16] #[MW]
Cost_of_energy_wind=0


# Wind farm and generators together [length: 4+12=16]

WIND_AND_GENERATOR=["W1","W2","W3","W4","G1","G2","G3","G4","G5","G6","G7","G8","G9","G10","G11","G12"]
WG=length(WIND_AND_GENERATOR)
Location_WG = [3 5 16 21 1 2 7 13 15 15 16 18 21 22 23 23] # node
Production_cost_WG = [0 0 0 0 13.32 13.32 20.7 20.93 26.11 10.52 10.52 6.02 5.47 7 10.52 10.89] #[$/MW]
PROD_Capacity_WG = [500 500 350 350 106.4 106.4 245 413.7 42 108.5 108.5 280 280 210 217 245] #MW  ##### change
Maximum_upward_reserve_WG = [0 0 0 0 48 48 84 216 42 36 36 60 60 48 72 48] #MW
Maximum_downward_reserve_WG = [0 0 0 0 48 48 84 216 42 36 36 60 60 48 72 48] #MW
Upward_reserve_cost_WG = [0 0 0 0 1.68 1.68 3.30 4.07 1.89 5.48 5.48 4.98 5.53 8.00 3.45 5.11] #[$/MW]
Downward_reserve_cost_WG = [0 0 0 0 2.32 2.32 4.67 3.93 3.11 3.52 3.52 5.02 4.97 6.00 2.52 2.89] #[$/MW]
Upward_reserve_cost_E = 3
Downward_reserve_cost_E = 2.5

nd=Normal(0,0.3)

PROD_Capacity_WG_t=zeros(WG,T)

wind_variability=zeros(WG,T)
for wg=1:W
  wind_variability[wg,:]=rand(nd,T)
end
for t=1:T
for wg=W+1:WG
  wind_variability[wg,t]=0
end
end

capacity_factor=[0.35 0.37 0.38 0.4 1 1 1 1 1 1 1 1 1 1 1 1]

for t=1:T
  for wg=1:WG
    PROD_Capacity_WG_t[wg,t]=PROD_Capacity_WG[wg]*capacity_factor[wg]+PROD_Capacity_WG[wg]*wind_variability[wg,t]*capacity_factor[wg]
  end
end


# Demand  [length: 17]
Location_demand = [1 2 3 4 5 6 7 8 9 10 13 14 15 16 18 19 20] #node
Consumption_demand = [84 75 139 58 55 106 97 132 135 150 205 150 245 77 258 141 100] #MW
time_demand=[0.2 0.2 0.2 0.3 0.4 0.6 0.9 1.1 1.1 1 0.9 0.8 0.9 1 0.9 1.1 1 1.2 1.1 0.8 0.8 0.8 0.6 0.4]

demand_fin=zeros(D,T)

for t=1:T
  for d=1:D
    demand_fin[d,t]=Consumption_demand[d]*time_demand[t]
  end
end


Bid_Price_demand=zeros(D,T)

for t=1:T
Random.seed!(t)
Bid_Price_demand[:,t] = sort(rand(15:100,D),rev=true)  # bid price random array
end


# electrolyzer

kg_to_MWh=1/18

electrolyzer_capacity=zeros(WG)
min_H2_per_electro=30000


for wg=1:W
    if sum(PROD_Capacity_WG_t[wg,t] for t=1:T) >= min_H2_per_electro*kg_to_MWh   # if with the DA it cannot reach te minimum to be activated then it is forced to 0
    electrolyzer_capacity[wg]=Installed_capacity_W[wg]/2
    end
end


E2 = Model(Gurobi.Optimizer)

@variable(E2, r_up_wg[1:WG,1:T]>=0)      #  =0 for the first 4 (wind farms)  -> capacity=0
@variable(E2, r_down_wg[1:WG,1:T]>=0)    #  =0 for the first 4 (wind farms)
@variable(E2, r_up_e[1:WG,1:T]>=0)       # 
@variable(E2, r_down_e[1:WG,1:T]>=0)     # 
@variable(E2,x_wg[1:WG,1:T])  # power production per each wind farm and generator [array of float]
@variable(E2,demand_covered[1:D,1:T])    # demand covered per each time slot ( cosidering that not all the demand is always covered )
@variable(E2,H2_electrolyzer[1:WG,1:T])   # kg of H2 produced of each electrolyzer at each time slot


@constraint(E2,[t=1:T], sum(r_up_wg[wg,t]+r_up_e[wg,t] for wg=1:WG) >= 0.2*sum(demand_fin[d,t] for d=1:D))           # minimum required up
@constraint(E2,[t=1:T], sum(r_down_wg[wg,t]+r_down_e[wg,t] for wg=1:WG) >= 0.15*sum(demand_fin[d,t] for d=1:D))      # minimum required down

@constraint(E2,[t=1:T,wg=1:WG], 0 <= r_up_wg[wg,t] <= Maximum_upward_reserve_WG[wg])
@constraint(E2,[t=1:T,wg=1:WG], 0 <= r_down_wg[wg,t] <= Maximum_downward_reserve_WG[wg])
#@constraint(E2,[t=1:T,wg=1:WG], r_down_wg[wg,t] <= PROD_Capacity_WG[wg] - r_up_wg[wg,t])  

@constraint(E2,[t=1:T,wg=1:WG], 0 <= r_up_e[wg,t] <= electrolyzer_capacity[wg]*0.1)        # 20% of capacity as maximum upward reserve for electrolyzer
@constraint(E2,[t=1:T,wg=1:WG], 0 <= r_down_e[wg,t] <= electrolyzer_capacity[wg]*0.05)     # 15% of capacity as maximum downward reserve for electrolyzer

@constraint(E2,[wg=1:WG,t=1:T], r_down_wg[wg,t] <= x_wg[wg,t])      # general capacity constraint JUST FOR GENERATORS regardin reserves
@constraint(E2,[wg=1:WG,t=1:T], x_wg[wg,t] <=PROD_Capacity_WG_t[wg,t] - r_up_wg[wg,t])      # general capacity constraint JUST FOR GENERATORS regardin reserves
@constraint(E2,[wg=1:WG,t=1:T], r_down_wg[wg,t] + r_up_e[wg,t] <= x_wg[wg,t] + H2_electrolyzer[wg,t]*kg_to_MWh)      # general capacity constraint
@constraint(E2,[wg=1:WG,t=1:T],  x_wg[wg,t] + H2_electrolyzer[wg,t]*kg_to_MWh <= PROD_Capacity_WG_t[wg,t] - r_up_wg[wg,t] - r_down_e[wg,t])      # general capacity constraint
@constraint(E2,[wg=1:WG,t=1:T], r_up_e[wg,t] <= H2_electrolyzer[wg,t]*kg_to_MWh)  # electrolyzer: h2 produced just by wind farm  [cap=0 in generators]
@constraint(E2,[wg=1:WG,t=1:T],  H2_electrolyzer[wg,t]*kg_to_MWh <= electrolyzer_capacity[wg]- r_down_e[wg,t])  # electrolyzer: h2 produced just by wind farm  [cap=0 in generators]

@constraint(E2,lambda[t=1:T],  sum(x_wg[wg,t] for wg=1:WG) - sum(demand_covered[d,t] for d=1:D) == 0)    # demand = power-electrolyzer  
@constraint(E2,[d=1:D,t=1:T], 0<=demand_covered[d,t]<=demand_fin[d,t])

@constraint(E2,[wg=1:W],sum(H2_electrolyzer[wg,t] for t=1:T) >= min_H2_per_electro*(electrolyzer_capacity[wg]==0 ? 0 : 1))   # the electrolyzer has to produce more than the amount SET (30 tons)
@constraint(E2, sum(H2_electrolyzer[wg,t] for wg=1:WG,t=1:T)>=2*min_H2_per_electro)

@objective(E2,Max,  sum(Bid_Price_demand[d,t]*demand_covered[d,t] for d=1:D,t=1:T) 
                  - sum(Production_cost_WG[wg]*(x_wg[wg,t] + H2_electrolyzer[wg,t]*kg_to_MWh) for wg=1:WG,t=1:T)
                  -(sum(Upward_reserve_cost_WG[wg]*r_up_wg[wg,t] for wg=1:WG,t=1:T) 
                  + sum(Downward_reserve_cost_WG[wg]*r_down_wg[wg,t] for wg=1:WG,t=1:T) 
                  + sum(Upward_reserve_cost_E*r_up_e[wg,t] for wg=1:WG,t=1:T) 
                  + sum(Downward_reserve_cost_E*r_down_e[wg,t] for wg=1:WG,t=1:T)))


optimize!(E2)

############################### market price #########################


market_price=zeros(T)

for t=1:T
  market_price[t]=value(dual.(lambda[t]))
end



# ########################## printing stuff ##################################


for t=1:T
    println("Market Price (",TIME_SLOT[t],"): ", @sprintf("%.2f", market_price[t]) , " \$/MWh")    # market price
end



# H2_per_day=zeros(WG)

# for wg=1:WG
# H2_per_day[wg]= sum(value(H2_electrolyzer[wg,t]) for t=1:T)
# end



# println("\n")
# println("DAILY PROFIT & POWER FOR EACH GENERATOR:\n ")

# profit=zeros(WG)
# generation_day=zeros(WG)
# grid_day=zeros(WG)

# for wg=1:WG
#      profit[wg] = sum(value(x_wg[wg,t])*market_price[t] - (value(x_wg[wg,t])*Production_cost_WG[wg]) - value(H2_electrolyzer[wg,t])*kg_to_MWh*Production_cost_WG[wg] for t=1:T)
#      generation_day[wg]= sum(value(x_wg[wg,t]) for t=1:T) + value(H2_per_day[wg]*kg_to_MWh)  ## generation is to the grid and h2 production
#      grid_day[wg]=sum(value(x_wg[wg,t]) for t=1:T)      ## power produce to match the demand
#      println(WIND_AND_GENERATOR[wg], " Profit: ", @sprintf("%.2f", profit[wg]), " \$"," - Total power: ", @sprintf("%.2f", generation_day[wg]), " (grid: " ,@sprintf("%.2f", value(grid_day[wg])) , ") - ( Mwh for H2: " , @sprintf("%.2f", H2_per_day[wg]*kg_to_MWh) , " equal to ", @sprintf("%.2f", H2_per_day[wg])," kg of H2) - Production cost: ", value(Production_cost_WG[wg]) )
# end

# generation_hours=zeros(WG,T)

# for wg=1:WG
#     for t=1:T
#         generation_hours[wg,t]= value(x_wg[wg,t]+H2_electrolyzer[wg,t]*kg_to_MWh)
#     end
# end


# println("\n")

# println("More often marginal generators:")

# println("\n")

# for t=1:T
#     println("GENERATION [MWh]: ", WIND_AND_GENERATOR[5]," (",TIME_SLOT[t],"): ", @sprintf("%.2f",value(generation_hours[5,t]) ) , " - ", WIND_AND_GENERATOR[6]," (",TIME_SLOT[t],"): ", @sprintf("%.2f",value(generation_hours[6,t]) ) , " - ", WIND_AND_GENERATOR[7]," (",TIME_SLOT[t],"): ", @sprintf("%.2f",value(generation_hours[7,t]) ), " - ", WIND_AND_GENERATOR[16]," (",TIME_SLOT[t],"): ", @sprintf("%.2f",value(generation_hours[16,t]) ) )  ## generation G3 (the most marginal producer)
# end



# println("\n")

# println("SOCIAL WELFARE : $(objective_value(B1)) \$")


# println("\n")
