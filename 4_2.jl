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

Capacity_G = [106.4 106.4 245 413.7 42 108.5 108.5 280 280 210 217 245] #MW



# Wind farms [length: 4]
Location_W = [3 5 16 21] #node
Installed_capacity_W= [500 500 300 300] #[MW]
Day_ahead_forecast_W = [120.54 115.52 53.34 38.16] #[MW]
Cost_of_energy_wind=0


# Wind farm and generators together [length: 4+17=21]

WIND_AND_GENERATOR=["W1","W2","W3","W4","G1","G2","G3","G4","G5","G6","G7","G8","G9","G10","G11","G12"]
WG=length(WIND_AND_GENERATOR)
Location_WG = [3 5 16 21 1 2 7 13 15 15 16 18 21 22 23 23] # node
Production_cost_WG = [0 0 0 0 13.32 13.32 20.7 20.93 26.11 10.52 10.52 6.02 5.47 7 10.52 10.89] #[$/MW]

PROD_Capacity_WG = [500 500 300 300 106.4 106.4 245 413.7 42 108.5 108.5 280 280 210 217 245] #MW

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
capacity_factor=[0.31 0.33 0.34 0.36 1 1 1 1 1 1 1 1 1 1 1 1]
for t=1:T
  for wg=1:WG
    PROD_Capacity_WG_t[wg,t]=PROD_Capacity_WG[wg]*capacity_factor[wg]+PROD_Capacity_WG[wg]*wind_variability[wg,t]*capacity_factor[wg]
  end
end


# Demand  [length: 17]
Location_demand = [1 2 3 4 5 6 7 8 9 10 13 14 15 16 18 19 20] #node
Consumption_demand = [84 75 139 58 55 106 97 132 135 150 205 150 245 77 258 141 100] #MW

time_demand=[0.2 0.2 0.2 0.3 0.4 0.6 0.9 1.1 1.1 1 0.9 0.8 0.9 1 0.9 1.1 1 1.2 1.1 0.8 0.8 0.8 0.6 0.4]

Bid_Price_demand=zeros(D,T)

for t=1:T
Random.seed!(t)
Bid_Price_demand[:,t] = sort(rand(15:100,D),rev=true)  # bid price random array
end

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


# Model
B1 = Model(Gurobi.Optimizer)

@variable(B1,x_wg[1:WG,1:T]>=0)  # power production per each wind farm and generator [array of float]
@variable(B1,demand_covered[1:D,1:T]>=0)    # demand covered per each time slot ( cosidering that not all the demand is always covered )
@variable(B1,H2_electrolyzer[1:WG,1:T]>=0)   # kg of H2 produced of each electrolyzer at each time slot


@constraint(B1,mu[wg=1:WG,t=1:T], x_wg[wg,t]<=PROD_Capacity_WG_t[wg,t])      # general capacity constraint
@constraint(B1,[wg=1:WG,t=1:T], x_wg[wg,t] + H2_electrolyzer[wg,t]*kg_to_MWh<=PROD_Capacity_WG_t[wg,t])      # general capacity constraint
@constraint(B1,[wg=1:WG,t=1:T], H2_electrolyzer[wg,t]*kg_to_MWh <= electrolyzer_capacity[wg])  # electrolyzer: h2 produced just by wind farm  [cap=0 in generators]

@constraint(B1,lambda[t=1:T],  sum(x_wg[wg,t] for wg=1:WG) -sum(demand_covered[d,t] for d=1:D) == 0)    # demand = power-electrolyzer  
@constraint(B1,[d=1:D,t=1:T], demand_covered[d,t]<=demand_fin[d,t])

@constraint(B1,[wg=1:W],sum(H2_electrolyzer[wg,t] for t=1:T) >= min_H2_per_electro*(electrolyzer_capacity[wg]==0 ? 0 : 1))   # the electrolyzer has to produce more than the amount SET (30 tons)
@constraint(B1, sum(H2_electrolyzer[wg,t] for wg=1:WG,t=1:T)>=2*min_H2_per_electro)

@objective(B1,Max, sum(Bid_Price_demand[d,t]*demand_covered[d,t] for d=1:D,t=1:T) - sum(Production_cost_WG[wg]*(x_wg[wg,t] + H2_electrolyzer[wg,t]*kg_to_MWh) for wg=1:WG,t=1:T))

optimize!(B1)

############################### market price #########################


market_price=zeros(T)

for t=1:T
  market_price[t]=value(dual.(lambda[t]))
end


println("\n")


##########################################################################################  time slot tt

# wind data 

nd=Normal(0,0.01)

tt=8           # time slot chosen
gg=W+8        # generator failed (the first 4 are wind so gg=9 means G4, W=4)

forecast_error=zeros(WG)

for wg=1:W
    forecast_error[wg]=rand(nd)
end
for wg=W+1:WG
    forecast_error[wg]=0
end


day_ahead_price=market_price[tt]

old_demand=zeros(D)

for d=1:D
        old_demand[d]= value(demand_covered[d,tt])
end

old_production=zeros(WG)

for wg=1:WG
        old_production[wg]= value(x_wg[wg,tt])
end
shut_down=zeros(WG)
shut_down[gg]=-old_production[gg]

old_hydrogen=zeros(WG)

for wg=1:WG
        old_hydrogen[wg]= value(H2_electrolyzer[wg,tt])
end




DUE=Model(Gurobi.Optimizer)

@variable(DUE,up_reg[1:WG]>=0)              # UP supply < demand - INCREASE supply, decreases hydrogen production then more electricity is used for the grid -> more supply
@variable(DUE,down_reg[1:WG]>=0)            # DOWN supply > demand - DECREASE supply, produce more hydrogen, increase hydrogen production so less electricity goes for the grid -> decrease supply     


    # if sum(forecast_error[wg]*(old_production[wg]+old_hydrogen[wg]*kg_to_MWh) + shut_down[wg] for wg=1:WG) <= 0
    #     @constraint(DUE, sum(forecast_error[wg]*(old_production[wg]+old_hydrogen[wg]*kg_to_MWh)+shut_down[wg]  for wg=1:WG) ==  sum(-up_reg[wg] for wg=1:WG) )   
    #     @constraint(DUE, 0 ==  sum(down_reg[wg] for wg=1:WG))      
    # else
    #     @constraint(DUE, sum(forecast_error[wg]*(old_production[wg]+old_hydrogen[wg]*kg_to_MWh)  + shut_down[wg] for wg=1:WG) ==  sum( down_reg[wg] for wg=1:WG))   
    #     @constraint(DUE, 0 ==  sum(-up_reg[wg] for wg=1:WG) )   
    # end



@constraint(DUE,up, sum(forecast_error[wg]*(old_production[wg]+old_hydrogen[wg]) + shut_down[wg] for wg=1:WG) ==  sum(-up_reg[wg] + down_reg[wg] for wg=1:WG))     # balance contraint
@constraint(DUE, [wg=1:WG], 0 <= down_reg[wg]<=old_production[wg])                                                           
@constraint(DUE,  [wg=1:WG], 0 <= up_reg[wg] <= PROD_Capacity_WG_t[wg,tt] - old_hydrogen[wg]*kg_to_MWh - old_production[wg])       
@constraint(DUE, [wg=gg], 0>=up_reg[wg])          # the shut down generator can't provide any regulation
@constraint(DUE, [wg=gg], 0>=down_reg[wg])        # the shut down generator can't provide any regulation


@objective(DUE, Min, sum(up_reg[wg]*(day_ahead_price+0.12*Production_cost_WG[wg]) for wg=1:WG) - sum(down_reg[wg]*(day_ahead_price-0.15*Production_cost_WG[wg]) for wg=1:WG))

optimize!(DUE)

println("\n")



println("\n")

for wg=1:WG
    println("upward (",TIME_SLOT[tt],"): ", "Generator ", WIND_AND_GENERATOR[wg],  @sprintf(" %.2f", value(up_reg[wg])) , " MWh" )   # market price
end

# println("\n")

# for wg=1:WG
#     println("downward (",TIME_SLOT[tt],"): ", "Generator ", WIND_AND_GENERATOR[wg],  @sprintf(" %.2f", value(down_reg[wg])) , " MWh" )   # market price
# end


balancing_price=value(dual.(up))

println("\nBalancing market price: ", @sprintf("%.2f",value(dual.(up))), " \$/MWh, Market Price: ", value(market_price[tt]))

println("\n")
profit=zeros(WG)

for wg=1:WG
  profit[wg] =  (forecast_error[wg]>=0  ? forecast_error[wg] : 0)*(old_production[wg]+old_hydrogen[wg])*(balancing_price-Production_cost_WG[wg]) + value(up_reg[wg])*(balancing_price-Production_cost_WG[wg]) + (old_production[wg]+ shut_down[wg])*(day_ahead_price-Production_cost_WG[wg])
  println("Profit ",WIND_AND_GENERATOR[wg], @sprintf(" %.2f " , profit[wg]) , " \$")
end

tot_profit=sum(profit[wg] for wg=1:WG)
