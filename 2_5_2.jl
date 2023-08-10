using Gurobi,JuMP
using Plots, Random, Printf, XLSX, CSV, DataFrames, Distributions, MathOptInterface

# SETS and DATA

GEN_S=["S1","S2","S3","S4"]                  # price MAKER generators
GEN_O=["O1","O2","O3","O4"]                  # price TAKER generators
DEMAND=["D1","D2","D3","D4"]                 # demand
NODE=["N1","N2","N3","N4","N5","N6"]         # nodes
TIME_SLOT=["00-01","01-02","02-03","03-04","04-05","05-06","06-07","07-08","08-09","09-10","10-11","11-12","12-13","13-14","14-15","15-16","16-17","17-18","18-19","19-20","20-21","21-22","22-23","23-24"]

T=length(TIME_SLOT)
S=length(GEN_S)
O=length(GEN_O)
D=length(DEMAND)
N=length(NODE)

D_Location=[3 4 5 6]    # demand location
S_Location=[1 2 3 6]    # price MAKER generators locations
O_Location=[1 2 3 5]    # price TAKER generators locations

D_quantity=[200 400 300 250]         # MW
# D_bid_price=[26.5 24.7 23.1 22.5]    # euro/MWh
D_over_time =    [0.2 0.2 0.2 0.3 0.4 0.6 0.9 1.1 1.0 1.0 0.9 0.8 0.9 1.0 0.9 1.1 1.0 1.2 1.1 0.8 0.8 0.8 0.6 0.4]    # demand time variation
WIND_over_time = [0.6 0.7 1.0 1.0 1.3 1.1 0.9 0.8 0.9 0.6 0.7 0.8 0.6 1.0 0.8 0.8 0.9 0.9 0.8 0.7 0.6 0.5 0.3 0.3]    # wind time variation

D_bid_price_T=zeros(D,T)

for t=1:T
    Random.seed!(t)
    D_bid_price_T[:,t] = sort(rand(20:30,D),rev=true)  # bid price random array
end

D_quantity_T=zeros(D,T)
for t=1:T
  for d=1:D
    D_quantity_T[d,t]=D_quantity[d]*D_over_time[t]         ### the demand is not constant for each hour but varies during the day, making the price varying as well
  end
end

S_capacity=[155 100 155 197]          # MW
O_capacity=[0.75*450 350 210 80]      # MW
O_capacity_T=zeros(O,T)

for o=1:O
    for t=1:T
        if o==1
        O_capacity_T[o,t]= O_capacity[o]*WIND_over_time[t]
        else
            O_capacity_T[o,t]=O_capacity[o]
        end
    end
end


S_cost=[15.2 23.4 15.2 19.1]     # euro/MWh
O_cost=[0 5 20.1 24.7]           # euro/MWh

S_ramp=[90 85 90 120]    # MW/h
O_ramp=[0 350 170 80]    # MW/h

susceptance=50
BB=1/susceptance

Big_M = 10^4


TWO_FIVE_TWO= Model(Gurobi.Optimizer)

@variable(TWO_FIVE_TWO, S_prod[1:S,1:T])
@variable(TWO_FIVE_TWO, O_prod[1:O,1:T])

@variable(TWO_FIVE_TWO, lambda[1:T])

@variable(TWO_FIVE_TWO, S_alpha_offer[1:S,1:T])
@variable(TWO_FIVE_TWO, demand[1:D,1:T])

@variable(TWO_FIVE_TWO, mu_D_up[1:D,1:T])
@variable(TWO_FIVE_TWO, mu_D_down[1:D,1:T])

@variable(TWO_FIVE_TWO, mu_O_up[1:O,1:T])
@variable(TWO_FIVE_TWO, mu_O_down[1:O,1:T])

@variable(TWO_FIVE_TWO, mu_S_up[1:S,1:T])
@variable(TWO_FIVE_TWO, mu_S_down[1:S,1:T])

@variable(TWO_FIVE_TWO, epsi_D_up[1:D,1:T],Bin)                                                     # 11
@variable(TWO_FIVE_TWO, epsi_D_down[1:D,1:T],Bin)                                                   # 16

@variable(TWO_FIVE_TWO, epsi_O_up[1:O,1:T],Bin)                                                     # 21
@variable(TWO_FIVE_TWO, epsi_O_down[1:O,1:T],Bin)                                                   # 26

@variable(TWO_FIVE_TWO, epsi_S_up[1:S,1:T], Bin)                                                    # 31
@variable(TWO_FIVE_TWO, epsi_S_down[1:S,1:T], Bin)                                                  # 36

#@constraint(TWO_FIVE_TWO,[s=1:S,t=1:T], S_alpha_offer[s,t] >= S_cost[s])                                 # 1
@constraint(TWO_FIVE_TWO,[s=1:S,t=1:T], S_alpha_offer[s,t]>=0)                                           # 2
@constraint(TWO_FIVE_TWO,[d=1:D,t=1:T], - D_bid_price_T[d,t] + mu_D_up[d,t] - mu_D_down[d,t] + lambda[t] == 0)    # 3
@constraint(TWO_FIVE_TWO,[s=1:S,t=1:T], S_alpha_offer[s,t] + mu_S_up[s,t] - mu_S_down[s,t] - lambda[t] == 0)    # 4
@constraint(TWO_FIVE_TWO,[o=1:O,t=1:T], O_cost[o] + mu_O_up[o,t] - mu_O_down[o,t] - lambda[t] == 0)           # 5
@constraint(TWO_FIVE_TWO,[t=1:T], sum(demand[d,t] for d=1:D) - sum(S_prod[s,t] for s=1:S) - sum(O_prod[o,t] for o=1:O) == 0) # 6

@constraint(TWO_FIVE_TWO, [s=1:S,t=2:T], S_prod[s,t] <= S_prod[s,t-1] + S_ramp[s])       # ramp up  constraint for MAKER
@constraint(TWO_FIVE_TWO, [s=1:S,t=2:T], S_prod[s,t-1] - S_ramp[s] <= S_prod[s,t])       # ramp down constraint for MAKER
@constraint(TWO_FIVE_TWO, [o=2:O,t=2:T], O_prod[o,t] <= O_prod[o,t-1] + O_ramp[o])       # ramp up constraint for TAKER
@constraint(TWO_FIVE_TWO, [o=2:O,t=2:T], O_prod[o,t-1] - O_ramp[o] <= O_prod[o,t])       # ramp down constraint for TAKER

# DEMAND

@constraint(TWO_FIVE_TWO, [d=1:D,t=1:T], demand[d,t]<=D_quantity_T[d,t])                                     # 7
@constraint(TWO_FIVE_TWO,[d=1:D,t=1:T], mu_D_up[d,t]>=0)                                                 # 8
@constraint(TWO_FIVE_TWO, [d=1:D,t=1:T], D_quantity_T[d,t] - demand[d,t] <= epsi_D_up[d,t]*Big_M)              # 9
@constraint(TWO_FIVE_TWO,[d=1:D,t=1:T], mu_D_up[d,t] <= (1 - epsi_D_up[d,t])*Big_M)                        # 10
# 11 is in the variable
@constraint(TWO_FIVE_TWO,[d=1:D,t=1:T], demand[d,t] >= 0)                                                # 12
@constraint(TWO_FIVE_TWO,[d=1:D,t=1:T], mu_D_down[d,t] >= 0)                                             # 13
@constraint(TWO_FIVE_TWO,[d=1:D,t=1:T], demand[d,t] <= epsi_D_down[d,t]*Big_M)                             # 14
@constraint(TWO_FIVE_TWO,[d=1:D,t=1:T], mu_D_down[d,t] <= (1 - epsi_D_down[d,t])*Big_M)                    # 15
# 16 is in the variable

# PRICE MAKER - LEADER - S

@constraint(TWO_FIVE_TWO, [s=1:S,t=1:T], S_prod[s,t]<=S_capacity[s])                                     # 17
@constraint(TWO_FIVE_TWO,[s=1:S,t=1:T], mu_S_up[s,t]>=0)                                                 # 18
@constraint(TWO_FIVE_TWO, [s=1:S,t=1:T], S_capacity[s] - S_prod[s,t] <= epsi_S_up[s,t]*Big_M)              # 19
@constraint(TWO_FIVE_TWO,[s=1:S,t=1:T], mu_S_up[s,t] <= (1 - epsi_S_up[s,t])*Big_M)                        # 20
# 21 is in the variable
@constraint(TWO_FIVE_TWO,[s=1:S,t=1:T], S_prod[s,t] >= 0)                                                # 22
@constraint(TWO_FIVE_TWO,[s=1:S,t=1:T], mu_S_down[s,t] >= 0)                                             # 23
@constraint(TWO_FIVE_TWO,[s=1:S,t=1:T], S_prod[s,t] <= epsi_S_down[s,t]*Big_M)                             # 24
@constraint(TWO_FIVE_TWO,[s=1:S,t=1:T], mu_S_down[s,t] <= (1 - epsi_S_down[s,t])*Big_M)                    # 25
# 26 is in the variable

# PRICE TAKER - FOLLOWERS - O

@constraint(TWO_FIVE_TWO, [o=1:O,t=1:T], O_prod[o,t]<=O_capacity_T[o,t])                                     # 27
@constraint(TWO_FIVE_TWO,[o=1:O,t=1:T], mu_O_up[o,t]>=0)                                                 # 28
@constraint(TWO_FIVE_TWO, [o=1:O,t=1:T], O_capacity_T[o,t] - O_prod[o,t] <= epsi_O_up[o,t]*Big_M)              # 29
@constraint(TWO_FIVE_TWO,[o=1:O,t=1:T], mu_O_up[o,t] <= (1 - epsi_O_up[o,t])*Big_M)                        # 30
# 31 is in the variable
@constraint(TWO_FIVE_TWO,[o=1:O,t=1:T], O_prod[o,t] >= 0)                                                # 32
@constraint(TWO_FIVE_TWO,[o=1:O,t=1:T], mu_O_down[o,t] >= 0)                                             # 33
@constraint(TWO_FIVE_TWO,[o=1:O,t=1:T], O_prod[o,t] <= epsi_O_down[o,t]*Big_M)                             # 34
@constraint(TWO_FIVE_TWO,[o=1:O,t=1:T], mu_O_down[o,t] <= (1 - epsi_O_down[o,t])*Big_M)                    # 35
# 36 is in the variable

@objective(TWO_FIVE_TWO, Max, sum( - sum(S_prod[s,t]*S_cost[s] for s=1:S) 
                                   + sum(D_bid_price_T[d,t]*demand[d,t] for d=1:D)
                                   - sum(O_cost[o]*O_prod[o,t] for o=1:O)
                                   - sum(mu_D_up[d,t]*D_quantity_T[d,t] for d=1:D)
                                   - sum(mu_O_up[o,t]*O_capacity_T[o,t] for o=1:O) for t=1:T)
)

start_time = time()
optimize!(TWO_FIVE_TWO)
end_time = time()



println("\n")

for t=1:T
    println("TIME SLOT ", TIME_SLOT[t],": \n")
    for s=1:S
        println("Offer Price ", GEN_S[s], @sprintf(" %.2f \$" , value(S_alpha_offer[s,t])), @sprintf(" - Power Producion: %.2f MW" , value(S_prod[s,t]))," - Production cost: ", @sprintf(" %.2f \$" , S_cost[s]), " - Capacity: ", @sprintf(" %.2f \$" , S_capacity[s]))
    end
    println("\n")
    for o=1:O
    println("Non-strategic ", GEN_O[o], @sprintf(" - Power Production: %.2f MW" , value(O_prod[o,t]))," - Production cost: ", @sprintf(" %.2f \$" , O_cost[o]), " - Capacity: ", @sprintf(" %.2f \$" , O_capacity_T[o,t]))
    end
    println("\n")
    println(@sprintf("Market clearing price: %.2f \$ ----------------------------------------" , value(lambda[t])))
    println("\n")
end 
println("\n")


# FEASIBILITY DATA TEST

println("Feasibility data test:\n")

tot_cap_T=zeros(T)
tot_dem_T=zeros(T)
feasibility_test_T=zeros(T)

for t=1:T
           tot_cap_T[t] =sum(O_capacity_T[o,t] for o=1:O) + sum(S_capacity[s] for s=1:S)
           tot_dem_T[t] = sum(D_quantity_T[d,t] for d=1:D) 
           feasibility_test_T[t] = tot_cap_T[t] - tot_dem_T[t]
           println("Time slot: ", TIME_SLOT[t], @sprintf(": %.2f MW more of total capacity - " , feasibility_test_T[t]), "Tot production: ", @sprintf(" %.2f MW " , tot_cap_T[t]), " - Tot demand: ", @sprintf(" %.2f MW " , tot_dem_T[t]) )

end

println("\n")

# Print number of variables and constraints
println("Number of variables: ", JuMP.num_variables(TWO_FIVE_TWO))
println("Number of constraints: ", JuMP.num_constraints(TWO_FIVE_TWO, count_variable_in_set_constraints=false))


# Print computational time
println("Computational time: ", end_time - start_time)